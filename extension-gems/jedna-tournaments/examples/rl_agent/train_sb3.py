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

from rl_agent.expert import (
    collect_dagger_dataset,
    collect_expert_dataset,
    merge_expert_datasets,
    pretrain_policy,
)
from rl_agent.rl_env import JednaVsProcessEnv
from rl_agent.table_sizes import parse_player_count_weights, parse_player_counts


def mask_fn(env: JednaVsProcessEnv):
    return env.valid_action_mask()


def build_dagger_beta_schedule(rounds, beta_start, raw_schedule=None):
    if rounds < 0:
        raise ValueError("--dagger-rounds cannot be negative")
    if not 0.0 <= beta_start <= 1.0:
        raise ValueError("--dagger-beta-start must be between 0 and 1")
    if raw_schedule:
        try:
            schedule = [float(value) for value in raw_schedule.split(",")]
        except ValueError as error:
            raise ValueError("--dagger-beta-schedule must contain numbers") from error
        if len(schedule) != rounds:
            raise ValueError(
                "--dagger-beta-schedule must contain one value per round"
            )
        if any(not 0.0 <= beta <= 1.0 for beta in schedule):
            raise ValueError("DAgger beta values must be between 0 and 1")
        return schedule
    if rounds == 0:
        return []
    if rounds == 1:
        return [beta_start]
    return [beta_start * (1.0 - index / (rounds - 1)) for index in range(rounds)]


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
    parser.add_argument(
        "--preserve-timestep-count",
        action="store_true",
        help=(
            "Keep a resumed model's timestep counter; --timesteps remains the "
            "number of additional steps"
        ),
    )
    parser.add_argument("--timeout", type=float, default=60.0)
    parser.add_argument(
        "--per-game-engine",
        action="store_true",
        help="Disable the default persistent Ruby engine for compatibility with stateful opponents",
    )
    parser.add_argument("--envs", type=int, default=4)
    parser.add_argument(
        "--player-counts",
        type=parse_player_counts,
        default=parse_player_counts("2-10"),
        help="Balanced per-episode table-size mixture, e.g. 2-10 or 2,4,6",
    )
    parser.add_argument(
        "--player-count-weights",
        type=parse_player_count_weights,
        help=(
            "Relative per-episode table-size weights, e.g. "
            "2:5,3:1,4:1,5:1,6:1,7:1; overrides --player-counts"
        ),
    )
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
    parser.add_argument("--dagger-rounds", type=int, default=0)
    parser.add_argument("--dagger-steps", type=int, default=500)
    parser.add_argument("--dagger-beta-start", type=float, default=0.5)
    parser.add_argument(
        "--dagger-beta-schedule",
        help="Comma-separated expert probabilities, one per DAgger round",
    )
    parser.add_argument("--dagger-epochs", type=int, default=1)
    parser.add_argument("--dagger-updates", type=int, default=0)
    parser.add_argument("--checkpoint-dir")
    parser.add_argument("--checkpoint-every", type=int, default=50_000)
    parser.add_argument("--eval-freq", type=int, default=0)
    parser.add_argument(
        "--eval-episodes",
        type=int,
        default=200,
        help="Evaluation episodes per table size",
    )
    parser.add_argument("--eval-opponent")
    parser.add_argument(
        "--eval-player-counts",
        type=parse_player_counts,
        help="Table sizes evaluated at each checkpoint; defaults to --player-counts",
    )
    return parser.parse_args()


def build_env(engine_path, opponent, args, player_counts=None):
    fixed_player_count = player_counts is not None
    base = JednaVsProcessEnv(
        engine_path=engine_path,
        opponent_cmd=opponent,
        player_counts=player_counts if fixed_player_count else args.player_counts,
        player_count_weights=(
            None if fixed_player_count else args.player_count_probabilities
        ),
        max_seconds=args.timeout,
        reward_scale=args.reward_scale,
        persistent_engine=not args.per_game_engine,
    )
    return ActionMasker(base, mask_fn)


def env_factory(engine_path, opponent, args, player_counts=None):
    def make_env():
        return build_env(engine_path, opponent, args, player_counts)

    return make_env


class MaskedEvalCallback(BaseCallback):
    def __init__(self, make_env, player_counts, frequency, episodes, best_path, seed):
        super().__init__()
        self.make_env = make_env
        self.player_counts = player_counts
        self.frequency = frequency
        self.episodes = episodes
        self.best_path = best_path
        self.seed = seed
        self.best_rate = -1.0

    def _on_step(self) -> bool:
        callback_frequency = max(self.frequency // self.training_env.num_envs, 1)
        if self.frequency <= 0 or self.n_calls % callback_frequency:
            return True

        rates = []
        for player_count in self.player_counts:
            env = self.make_env(player_count)
            wins = 0
            try:
                for episode in range(self.episodes):
                    observation, info = env.reset(
                        seed=self.seed + (player_count * 1_000_000) + episode
                    )
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
            rates.append(rate)
            print(
                f"[Evaluation] steps={self.num_timesteps} players={player_count} "
                f"wins={wins}/{self.episodes} rate={rate:.2%}"
            )

        rate = sum(rates) / len(rates)
        print(
            f"[Evaluation] steps={self.num_timesteps} "
            f"macro_rate={rate:.2%} table_sizes={','.join(map(str, self.player_counts))}"
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
        player_counts = args.eval_player_counts or args.player_counts
        callbacks.append(
            MaskedEvalCallback(
                lambda player_count: build_env(
                    engine_path, opponent, args, (player_count,)
                ),
                player_counts,
                args.eval_freq,
                args.eval_episodes,
                best_path,
                args.seed + 1_000_000,
            )
        )

    return CallbackList(callbacks) if callbacks else None


def main():
    args = parse_args()
    if args.player_count_weights:
        args.player_counts = tuple(
            count for count, _weight in args.player_count_weights
        )
        args.player_count_probabilities = tuple(
            weight for _count, weight in args.player_count_weights
        )
    else:
        args.player_count_probabilities = None
    try:
        beta_schedule = build_dagger_beta_schedule(
            args.dagger_rounds,
            args.dagger_beta_start,
            args.dagger_beta_schedule,
        )
    except ValueError as error:
        raise SystemExit(str(error)) from error
    if args.dagger_rounds > 0 and args.expert_steps <= 0:
        raise SystemExit("--expert-steps must be positive when DAgger is enabled")
    if args.dagger_rounds > 0 and args.dagger_steps <= 0:
        raise SystemExit("--dagger-steps must be positive when DAgger is enabled")
    if args.preserve_timestep_count and not args.resume:
        raise SystemExit("--preserve-timestep-count requires --resume")

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
                player_counts=args.player_counts,
                player_count_weights=args.player_count_probabilities,
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
            datasets = [(observations, actions, masks)]
            for round_index, beta in enumerate(beta_schedule):
                dagger_env = JednaVsProcessEnv(
                    engine_path,
                    expert_opponent,
                    player_counts=args.player_counts,
                    player_count_weights=args.player_count_probabilities,
                    max_seconds=args.timeout,
                    reward_scale=args.reward_scale,
                )
                try:
                    dataset = collect_dagger_dataset(
                        dagger_env,
                        args.expert,
                        model,
                        args.dagger_steps,
                        args.seed + ((round_index + 1) * 100_000),
                        beta,
                    )
                finally:
                    dagger_env.close()
                datasets.append(dataset)
                observations, actions, masks = merge_expert_datasets(*datasets)
                print(
                    f"[DAgger] round={round_index + 1}/{args.dagger_rounds} "
                    f"beta={beta:.3f} aggregate_steps={len(actions)}"
                )
                pretrain_policy(
                    model,
                    observations,
                    actions,
                    masks,
                    epochs=args.dagger_epochs,
                    batch_size=args.bc_batch_size,
                    seed=args.seed + round_index + 1,
                    updates=args.dagger_updates,
                )
            model.save(f"{args.model}_bc")

        if args.timesteps > 0:
            model.learn(
                total_timesteps=args.timesteps,
                callback=build_callbacks(engine_path, args),
                progress_bar=False,
                reset_num_timesteps=not args.preserve_timestep_count,
            )
        model.save(args.model)
        print(f"Saved model to {args.model}.zip")
    finally:
        env.close()


if __name__ == "__main__":
    main()
