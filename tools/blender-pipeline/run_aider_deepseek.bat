@echo off
title Local AI Deep Reasoning Agent (DeepSeek-R1 32B - AMD RX 7900 XTX)
echo ======================================================================
echo Launching Aider with Local DeepSeek-R1 32B (Reasoning Model)...
echo VRAM: AMD Radeon RX 7900 XTX (24 GB)
echo ======================================================================
set OLLAMA_API_BASE=http://127.0.0.1:11434
"C:\Users\ijito\.local\bin\aider.exe" --model ollama_chat/deepseek-r1:32b --no-check-update
pause
