@echo off
title Local AI Pair Programmer (Qwen 2.5 Coder 32B - AMD RX 7900 XTX)
echo ======================================================================
echo Launching Aider with Local Qwen 2.5 Coder 32B (Ollama ROCm Engine)...
echo VRAM: AMD Radeon RX 7900 XTX (24 GB)
echo ======================================================================
set OLLAMA_API_BASE=http://127.0.0.1:11434
"C:\Users\ijito\.local\bin\aider.exe" --model ollama_chat/qwen2.5-coder:32b --no-check-update
pause
