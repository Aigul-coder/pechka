@echo off
setlocal
cd /d "%~dp0"
if exist "%~dp0vendor\w64\w64devkit\bin\gcc.exe" set PATH=%~dp0vendor\w64\w64devkit\bin;%PATH%

set RL=%~dp0vendor\raylib-6.0_win64_mingw-w64
set GCC=

if exist "%~dp0vendor\w64\w64devkit\bin\gcc.exe" set GCC=%~dp0vendor\w64\w64devkit\bin\gcc.exe
if exist "%~dp0vendor\w64\bin\gcc.exe" set GCC=%~dp0vendor\w64\bin\gcc.exe
if exist "C:\WinLibs\mingw64\bin\gcc.exe" set GCC=C:\WinLibs\mingw64\bin\gcc.exe

if "%GCC%"=="" (
  echo GCC not found. Install WinLibs or extract w64devkit.
  exit /b 1
)

if not exist "%~dp0build" mkdir "%~dp0build"

"%GCC%" -std=c11 -O2 -Wall -finput-charset=UTF-8 -fexec-charset=UTF-8 -D_CRT_SECURE_NO_WARNINGS ^
  -I"%~dp0src" -I"%RL%\include" ^
  "%~dp0src\pechka.c" ^
  -L"%RL%\lib" -lraylib -lopengl32 -lgdi32 -lwinmm ^
  -o "%~dp0build\Pechka3D.exe"

if errorlevel 1 exit /b 1
copy /Y "%RL%\lib\raylib.dll" "%~dp0build\raylib.dll" >nul
if not exist "%~dp0build\assets" mkdir "%~dp0build\assets"
copy /Y "%~dp0assets\*.jpg" "%~dp0build\assets\" >nul
echo Built %~dp0build\Pechka3D.exe
