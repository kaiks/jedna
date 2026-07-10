#!/usr/bin/env python3
"""
Sample training script using SB3 MaskablePPO against a process opponent.

Requirements:
  pip install stable-baselines3 sb3-contrib gymnasium torch

Usage:
  python3 train_sb3.py --opponent "./crushing_agent.rb" \
                       --timesteps 10000 --model /tmp/jedna_maskppo
"""
import argparse
import os
import sys

from sb3_contrib.ppo_mask import MaskablePPO
from sb3_contrib.common.wrappers import ActionMasker

# Ensure the parent examples directory is importable as a package root
HERE = os.path.abspath(os.path.dirname(__file__))
EXAMPLES_DIR = os.path.abspath(os.path.join(HERE, ".."))
if EXAMPLES_DIR not in sys.path:
    sys.path.insert(0, EXAMPLES_DIR)

from rl_agent.rl_env import JednaVsProcessEnv


def mask_fn(env: JednaVsProcessEnv):
    return env.valid_action_mask()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--opponent", required=True, help="Opponent command string")
    parser.add_argument("--timesteps", type=int, default=20000)
    parser.add_argument("--model", default="/tmp/jedna_maskppo")
    parser.add_argument("--timeout", type=float, default=60.0, help="Per-episode timeout seconds")
    parser.add_argument("--envs", type=int, default=1, help="Number of parallel envs")
    parser.add_argument("--checkpoint-dir", default=None, help="Directory to save periodic checkpoints")
    parser.add_argument("--checkpoint-every", type=int, default=50000, help="Checkpoint frequency in env steps")
    parser.add_argument("--eval-freq", type=int, default=0, help="Evaluate every N steps (0 to disable)")
    parser.add_argument("--eval-episodes", type=int, default=200, help="Episodes per evaluation when enabled")
    args = parser.parse_args()

    engine_path = os.path.join(
        os.path.dirname(__file__),
        "..",
        "engine_bridge.rb",
    )
    engine_path = os.path.abspath(engine_path)

    # Build vectorized envs with action masking
    from stable_baselines3.common.vec_env import SubprocVecEnv, DummyVecEnv

    def make_env():
        def _thunk():
            base = JednaVsProcessEnv(engine_path=engine_path, opponent_cmd=args.opponent, max_seconds=args.timeout)
            return ActionMasker(base, mask_fn)
        return _thunk

    if args.envs > 1:
        env = SubprocVecEnv([make_env() for _ in range(args.envs)])
    else:
        env = DummyVecEnv([make_env()])

    # Use MultiInputPolicy for Dict observations
    model = MaskablePPO("MultiInputPolicy", env, verbose=1)

    # Callbacks: checkpoints and optional masked eval
    from stable_baselines3.common.callbacks import CheckpointCallback, BaseCallback, CallbackList

    callbacks = []
    if args.checkpoint_dir:
        os.makedirs(args.checkpoint_dir, exist_ok=True)
        callbacks.append(CheckpointCallback(save_freq=args.checkpoint_every, save_path=args.checkpoint_dir, name_prefix="ckpt"))

    class MaskedEvalCallback(BaseCallback):
        def __init__(self, make_env_fn, eval_freq: int, n_eval_episodes: int, best_path: str):
            super().__init__()
            self.make_env_fn = make_env_fn
            self.eval_freq = eval_freq
            self.n_eval_episodes = n_eval_episodes
            self.best_mean = -1e9
            self.best_path = best_path

        def _on_step(self) -> bool:
            if self.eval_freq <= 0:
                return True
            if self.num_timesteps > 0 and (self.num_timesteps % self.eval_freq == 0):
                # Run evaluation on a fresh env (non-vectorized) to measure current policy
                env = self.make_env_fn()
                wins = 0
                total = 0
                for _ in range(self.n_eval_episodes):
                    obs, info = env.reset()
                    done = False
                    while not done:
                        mask = info.get("action_mask")
                        action, _ = self.model.predict(obs, action_masks=mask, deterministic=True)
                        obs, reward, terminated, truncated, info = env.step(int(action))
                        done = terminated or truncated
                    total += 1
                    if reward > 0:
                        wins += 1
                mean = (wins / max(1, total)) * 100.0
                print(f"\n[Eval] steps={self.num_timesteps} episodes={total} win_rate={mean:.2f}%\n")
                if mean > self.best_mean:
                    self.best_mean = mean
                    # Save best model
                    path = os.path.join(self.best_path, f"best_{int(self.num_timesteps)}.zip")
                    try:
                        self.model.save(path)
                        print(f"[Eval] New best model saved to {path}")
                    except Exception as e:
                        print(f"[Eval] Failed to save best model: {e}")
                env.close()
            return True

    if args.eval_freq and args.eval_freq > 0:
        # Make a single non-vectorized eval env factory
        def make_eval_env():
            base = JednaVsProcessEnv(engine_path=engine_path, opponent_cmd=args.opponent, max_seconds=args.timeout)
            # Masked env for correct action selection
            return ActionMasker(base, mask_fn)

        # Best path defaults to checkpoint dir or model dir
        best_dir = args.checkpoint_dir or os.path.dirname(os.path.abspath(args.model)) or "/tmp"
        os.makedirs(best_dir, exist_ok=True)
        callbacks.append(MaskedEvalCallback(make_eval_env, args.eval_freq, args.eval_episodes, best_dir))

    cb = CallbackList(callbacks) if callbacks else None
    model.learn(total_timesteps=args.timesteps, callback=cb)
    model.save(args.model)
    env.close()
    print(f"Saved model to {args.model}")


if __name__ == "__main__":
    main()
