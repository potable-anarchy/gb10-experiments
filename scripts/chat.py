#!/usr/bin/env python3
"""
Interactive chat client for the trtllm-serve OpenAI-compatible API.
Stdlib only -- no pip install required.

Usage:  python3 chat.py [--endpoint URL] [--model MODEL]
"""
import json
import sys
import time
import urllib.request
import urllib.error

ENDPOINT = "http://localhost:8355/v1/chat/completions"
MODEL = "huihui-ai/Llama-3.3-70B-Instruct-abliterated"
MAX_TOKENS = 800
TEMPERATURE = 0.7

history = []
system_prompt = None
last_stats = None


def send(messages):
    body = {
        "model": MODEL,
        "messages": messages,
        "max_tokens": MAX_TOKENS,
        "temperature": TEMPERATURE,
    }
    req = urllib.request.Request(
        ENDPOINT,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=600) as resp:
            data = json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        return None, f"HTTP {e.code}: {e.read().decode()[:300]}", 0
    except Exception as e:
        return None, f"ERROR: {e}", 0
    elapsed = time.time() - t0
    msg = data["choices"][0]["message"]["content"]
    usage = data.get("usage", {})
    return msg, usage, elapsed


def main():
    global system_prompt, history, last_stats
    print(f"chat -> {ENDPOINT}")
    print(f"model: {MODEL}")
    print("commands: /reset  /system <text>  /tokens  /quit\n")
    while True:
        try:
            user = input("\033[1;36myou>\033[0m ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return
        if not user:
            continue
        if user == "/quit":
            return
        if user == "/reset":
            history = []
            print("(history cleared)")
            continue
        if user.startswith("/system "):
            system_prompt = user[len("/system "):]
            print(f"(system: {system_prompt[:60]}...)")
            continue
        if user == "/tokens":
            print(f"(last: {last_stats})")
            continue

        history.append({"role": "user", "content": user})
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.extend(history)

        msg, usage, elapsed = send(messages)
        if msg is None:
            print(f"\033[31m{usage}\033[0m")
            history.pop()
            continue

        history.append({"role": "assistant", "content": msg})
        comp = usage.get("completion_tokens", 0) if isinstance(usage, dict) else 0
        tps = comp / elapsed if elapsed > 0 else 0
        last_stats = f"tokens={comp} time={elapsed:.1f}s tok/s={tps:.2f}"

        print(f"\033[1;32mllm>\033[0m {msg}")
        print(f"\033[2m({last_stats})\033[0m\n")


if __name__ == "__main__":
    main()
