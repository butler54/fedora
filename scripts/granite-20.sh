#!/usr/bin/env bash
llama-server -c 4096 --host 0.0.0.0 -t 16 --mlock -m /home/chris/go/src/huggingface.co/ibm-granite/granite-20b-code-instruct-8k-GGUF/granite-20b-code-instruct.Q4_K_M.gguf
