#!/usr/bin/env python3
"""Train a masked PPO agent with optional expert imitation warm-start."""

import argparse
import os
import sys

import torch
from sb3_contrib.common.wrappers import ActionMasker
from sb3_contrib.ppo_mask import MaskablePPO
from stable_baselines3.common.callbacks import BaseCallback, CallbackList, CheckpointCallback
from stable_baselines3.common.vec_env import DummyVecEnv, SubprocVecEnv

HERE = os.path.abspath(os.path.dirname(__file__))
EXAMPLES_DIR = os.path.abspath(os.path.join(HERE, ".."))
if EXAMPLES_DIR not in sys.path:
    sys.path.insert(0, EXAMPLES_DIR)

from rl_agent.expert import collect_expert_dataset, pretrain_policy
from rl_agent.rl_env import JednaVsProcessEnv


def mask_fn(env: JednaVsProcessEnv):
    return env.valid_action_mask()


def parse_args():
    parser = argparse.ArgumentParser(
        description="Behavior-clone an expert, then fine-tune with MaskablePPO"
    )
    parser.add_argument(
        "--opponent",
        action="append",
        required=True,
        help="Opponent command; repeat to train against a mixture",
    )
    parser.add_argument("--timesteps", type=int, default=200_000)
    parser.add_argument("--model", default="/tmp/jedna_maskppo")
    parser.add_argument("--resume", help="Existing model to continue training")
    parser.add_argument("--timeout", type=float, default=60.0)
    parser.add_argument(
        "--per-game-engine",
        action="store_true",
        help="Disable the default persistent Ruby engine for compatibility with stateful opponents",
    )
    parser.add_argument("--envs", type=int, default=4)
    parser.add_argument("--seed", type=int, default=12_345)
    parser.add_argument("--device", default="auto")
    parser.add_argument("--reward-scale", type=float, default=0.05)
    parser.add_argument("--n-steps", type=int, default=512)
    parser.add_argument("--batch-size", type=int, default=256)
    parser.add_argument("--ppo-epochs", type=int, default=5)
    parser.add_argument("--gamma", type=float, default=0.995)
    parser.add_argument("--ent-coef", type=float, default=0.01)
    parser.add_argument("--expert", help="JSON-lines agent used as behavior-cloning teacher")
    parser.add_argument("--expert-opponent", help="Opponent used while collecting expert states")
    parser.add_argument("--expert-steps", type=int, default=0)
    parser.add_argument("--bc-epochs", type=int, default=5)
    parser.add_argument("--bc-batch-size", type=int, default=256)
    parser.add_argument("--checkpoint-dir")
    parser.add_argument("--checkpoint-every", type=int, default=50_000)
    parser.add_argument("--eval-freq", type=int, default=0)
    parser.add_argument("--eval-episodes", type=int, default=200)
    parser.add_argument("--eval-opponent")
    return parser.parse_args()


def build_env(engine_path, opponent, args):
    base = JednaVsProcessEnv(
        engine_path=engine_path,
        opponent_cmd=opponent,
        max_seconds=args.timeout,
        reward_scale=args.reward_scale,
        persistent_engine=not args.per_game_engine,
    )
    return ActionMasker(base, mask_fn)


def env_factory(engine_path, opponent, args):
    def make_env():
        return build_env(engine_path, opponent, args)

    return make_env


class MaskedEvalCallback(BaseCallback):
    def __init__(self, make_env, frequency, episodes, best_path, seed):
        super().__init__()
        self.make_env = make_env
        self.frequency = frequency
        self.episodes = episodes
        self.best_path = best_path
        self.seed = seed
        self.best_rate = -1.0

    def _on_step(self) -> bool:
        callback_frequency = max(self.frequency // self.training_env.num_envs, 1)
        if self.frequency <= 0 or self.n_calls % callback_frequency:
            return True

        env = self.make_env()
        wins = 0
        try:
            for episode in range(self.episodes):
                observation, info = env.reset(seed=self.seed + episode)
                done = False
                while not done:
                    action, _ = self.model.predict(
                        observation,
                        action_masks=info["action_mask"],
                        deterministic=True,
                    )
                    action_index = action.item() if hasattr(action, "item") else action
                    observation, _reward, terminated, truncated, info = env.step(
                        int(action_index)
                    )
                    done = terminated or truncated
                wins += int(info.get("winner") == "agent1")
        finally:
            env.close()

        rate = wins / self.episodes
        print(
            f"[Evaluation] steps={self.num_timesteps} "
            f"wins={wins}/{self.episodes} rate={rate:.2%}"
        )
        if rate > self.best_rate:
            self.best_rate = rate
            self.model.save(os.path.join(self.best_path, "best_model"))
        return True


def create_model(env, args):
    if args.resume:
        return MaskablePPO.load(args.resume, env=env, device=args.device)

    policy_kwargs = {
        "activation_fn": torch.nn.ReLU,
        "net_arch": {"pi": [256, 256], "vf": [256, 256]},
    }
    return MaskablePPO(
        "MultiInputPolicy",
        env,
        learning_rate=3e-4,
        n_steps=args.n_steps,
        batch_size=args.batch_size,
        n_epochs=args.ppo_epochs,
        gamma=args.gamma,
        gae_lambda=0.95,
        ent_coef=args.ent_coef,
        policy_kwargs=policy_kwargs,
        verbose=1,
        seed=args.seed,
        device=args.device,
    )


def build_callbacks(engine_path, args):
    callbacks = []
    if args.checkpoint_dir:
        os.makedirs(args.checkpoint_dir, exist_ok=True)
        callbacks.append(
            CheckpointCallback(
                save_freq=max(args.checkpoint_every // args.envs, 1),
                save_path=args.checkpoint_dir,
                name_prefix="checkpoint",
            )
        )

    if args.eval_freq > 0:
        best_path = args.checkpoint_dir or os.path.dirname(os.path.abspath(args.model))
        os.makedirs(best_path, exist_ok=True)
        opponent = args.eval_opponent or args.opponent[-1]
        callbacks.append(
            MaskedEvalCallback(
                env_factory(engine_path, opponent, args),
                args.eval_freq,
                args.eval_episodes,
                best_path,
                args.seed + 1_000_000,
            )
        )

    return CallbackList(callbacks) if callbacks else None


def main():
    args = parse_args()
    engine_path = os.path.abspath(os.path.join(HERE, "..", "engine_bridge.rb"))
    factories = [
        env_factory(engine_path, args.opponent[index % len(args.opponent)], args)
        for index in range(args.envs)
    ]
    env = SubprocVecEnv(factories) if args.envs > 1 else DummyVecEnv(factories)
    env.seed(args.seed)
    model = create_model(env, args)

    try:
        if args.expert_steps > 0:
            if not args.expert:
                raise SystemExit("--expert is required when --expert-steps is positive")
            expert_opponent = args.expert_opponent or args.opponent[0]
            expert_env = JednaVsProcessEnv(
                engine_path,
                expert_opponent,
                max_seconds=args.timeout,
                reward_scale=args.reward_scale,
            )
            try:
                observations, actions, masks = collect_expert_dataset(
                    expert_env,
                    args.expert,
                    args.expert_steps,
                    args.seed,
                )
            finally:
                expert_env.close()
            pretrain_policy(
                model,
                observations,
                actions,
                masks,
                epochs=args.bc_epochs,
                batch_size=args.bc_batch_size,
                seed=args.seed,
            )
            model.save(f"{args.model}_bc")

        if args.timesteps > 0:
            model.learn(
                total_timesteps=args.timesteps,
                callback=build_callbacks(engine_path, args),
                progress_bar=False,
            )
        model.save(args.model)
        print(f"Saved model to {args.model}.zip")
    finally:
        env.close()


if __name__ == "__main__":
    main()
