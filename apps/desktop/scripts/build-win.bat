@echo off
setlocal enabledelayedexpansion

REM ============================================================================
REM PilotDeck Windows Build Script
REM Usage: build-win.bat [--skip-install] [--skip-build] [--x64-only]
REM ============================================================================

set "REPO_ROOT=%~dp0..\..\..\"
set "DESKTOP_DIR=%~dp0..\"
set "UI_DIR=%REPO_ROOT%ui"
set "MEMORY_DIR=%REPO_ROOT%src\context\memory\edgeclaw-memory-core"
set "RESOURCES=%DESKTOP_DIR%resources"

set SKIP_INSTALL=0
set SKIP_BUILD=0
set X64_ONLY=0

for %%a in (%*) do (
    if "%%a"=="--skip-install" set SKIP_INSTALL=1
    if "%%a"=="--skip-build" set SKIP_BUILD=1
    if "%%a"=="--x64-only" set X64_ONLY=1
)

echo.
echo ========================================
echo  PilotDeck Windows Builder
echo ========================================
echo.

REM --- Step 1: Git pull (skip on CI / detached HEAD) ---
echo [1] Pulling latest from GitHub...
cd /d "%REPO_ROOT%"
git pull origin main
if errorlevel 1 (
    echo WARNING: git pull failed ^(ok on CI / detached HEAD^), continuing
) else (
    echo OK
)

REM --- Step 2: Install dependencies ---
if %SKIP_INSTALL%==0 (
    echo.
    echo [2] Installing dependencies...
    cd /d "%REPO_ROOT%"
    REM Root project is a pnpm workspace (packageManager: pnpm@10.32.1).
    REM Using npm here fails with "Cannot read properties of null (reading 'matches')".
    REM --shamefully-hoist flattens transitive deps to node_modules root (npm-style),
    REM so direct imports of transitive deps (e.g. @codemirror/view via @uiw/react-codemirror) resolve in vite.
    where pnpm >nul 2>nul && (
        call pnpm install --ignore-scripts
    ) || (
        call npm install --ignore-scripts
    )
    if errorlevel 1 (
        echo ERROR: root install failed
        exit /b 1
    )
    cd /d "%DESKTOP_DIR%"
    call npm install
    if errorlevel 1 (
        echo ERROR: desktop npm install failed
        exit /b 1
    )
    echo OK
) else (
    echo [2] Skipping install ^(--skip-install^)
)

REM --- Step 3: Download Node.js for Windows ---
if not exist "%RESOURCES%\node-bin\node.exe" (
    echo.
    echo [3] Downloading Node.js v22.14.0 for Windows x64...
    mkdir "%RESOURCES%\node-bin" 2>nul
    cd /d "%RESOURCES%\node-bin"
    curl -fsSL -o node-win-x64.zip https://nodejs.org/dist/v22.14.0/node-v22.14.0-win-x64.zip
    tar xf node-win-x64.zip node-v22.14.0-win-x64/node.exe
    move node-v22.14.0-win-x64\node.exe node.exe
    rd /s /q node-v22.14.0-win-x64
    del node-win-x64.zip
    echo OK: & node.exe --version
) else (
    echo [3] Node.js binary already present, skipping download
)

REM --- Step 3b: Rebuild native deps for bundled Node ABI ---
echo.
echo [3b] Rebuilding native deps for bundled Node...
cd /d "%REPO_ROOT%"
if exist node_modules\better-sqlite3\build rd /s /q node_modules\better-sqlite3\build
set "PATH=%RESOURCES%\node-bin;%PATH%"
set "NPM_CMD="
for /f "delims=" %%i in ('where npm.cmd 2^>nul') do (
    if not defined NPM_CMD set "NPM_CMD=%%i"
)
if not defined NPM_CMD (
    echo ERROR: npm.cmd not found
    exit /b 1
)
for %%i in ("%NPM_CMD%") do set "NPM_DIR=%%~dpi"
set "NPM_CLI=%NPM_DIR%node_modules\npm\bin\npm-cli.js"
if not exist "%NPM_CLI%" (
    echo ERROR: npm-cli.js not found: %NPM_CLI%
    exit /b 1
)
"%RESOURCES%\node-bin\node.exe" "%NPM_CLI%" rebuild better-sqlite3
if errorlevel 1 (
    echo ERROR: better-sqlite3 native rebuild failed
    exit /b 1
)
echo OK

REM --- Step 4: Download Bun for Windows ---
if exist "%RESOURCES%\bun-bin\bun.exe" goto :bun_done
echo.
echo [4] Downloading Bun v1.3.10 for Windows x64...
mkdir "%RESOURCES%\bun-bin" 2>nul
cd /d "%RESOURCES%\bun-bin"
curl -fsSL -o bun-win-x64.zip https://github.com/oven-sh/bun/releases/download/bun-v1.3.10/bun-windows-x64.zip
if errorlevel 1 (
    echo ERROR: Bun download failed
    exit /b 1
)
tar xf bun-win-x64.zip bun-windows-x64/bun.exe
move bun-windows-x64\bun.exe bun.exe
rd /s /q bun-windows-x64
del bun-win-x64.zip
echo OK: bun downloaded
:bun_done

REM --- Step 4b: Download Git for Windows (portable, provides bash.exe) ---
if exist "%RESOURCES%\git-bin\usr\bin\bash.exe" goto :git_done
echo.
echo [4b] Downloading Git for Windows portable (bash)...
mkdir "%RESOURCES%\git-bin" 2>nul
cd /d "%RESOURCES%\git-bin"
curl -fsSL -o PortableGit.7z.exe https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/PortableGit-2.47.1.2-64-bit.7z.exe
if errorlevel 1 (
    echo ERROR: Git portable download failed
    exit /b 1
)
PortableGit.7z.exe -y -o"%RESOURCES%\git-bin"
if errorlevel 1 (
    echo ERROR: Git portable extraction failed
    exit /b 1
)
del PortableGit.7z.exe
if not exist "%RESOURCES%\git-bin\usr\bin\bash.exe" (
    echo ERROR: bash.exe not found after extraction
    exit /b 1
)
echo OK: bash present
:git_done

REM --- Step 4c: Download Python embeddable + office skill deps ---
if exist "%RESOURCES%\python-bin\python.exe" goto :python_done
echo.
echo [4c] Downloading Python 3.13 embeddable for Windows x64...
mkdir "%RESOURCES%\python-bin" 2>nul
cd /d "%RESOURCES%\python-bin"
curl -fsSL -o python-embed.zip https://www.python.org/ftp/python/3.13.1/python-3.13.1-embed-amd64.zip
if errorlevel 1 (
    echo ERROR: Python embeddable download failed
    exit /b 1
)
tar xf python-embed.zip
if errorlevel 1 (
    echo ERROR: Python extraction failed
    exit /b 1
)
del python-embed.zip
if exist python313._pth powershell -Command "(Get-Content python313._pth) -replace '^#import site', 'import site' | Set-Content python313._pth"
curl -fsSL -o get-pip.py https://bootstrap.pypa.io/get-pip.py
python.exe get-pip.py --quiet
if errorlevel 1 (
    echo ERROR: pip bootstrap failed
    exit /b 1
)
del get-pip.py
python.exe -m pip install --quiet python-docx "lxml>=5.2,<7" openpyxl python-pptx pypdf pdfplumber reportlab PyMuPDF Pillow
if errorlevel 1 (
    echo ERROR: office python deps install failed
    exit /b 1
)
echo OK: python downloaded
:python_done

REM --- Step 4d: Download poppler (pdftoppm for PDF rendering) ---
if exist "%RESOURCES%\poppler-bin\Library\bin\pdftoppm.exe" goto :poppler_done
echo.
echo [4d] Downloading poppler for Windows...
mkdir "%RESOURCES%\poppler-bin" 2>nul
cd /d "%RESOURCES%"
curl -fsSL -o poppler.zip https://github.com/oschwartz10612/poppler-windows/releases/download/v24.08.0-0/Release-24.08.0-0.zip
if errorlevel 1 (
    echo ERROR: poppler download failed
    exit /b 1
)
cd /d "%RESOURCES%\poppler-bin"
tar xf "%RESOURCES%\poppler.zip" --strip-components=0
if errorlevel 1 (
    echo ERROR: poppler extraction failed
    exit /b 1
)
del "%RESOURCES%\poppler.zip"
if not exist "Library\bin\pdftoppm.exe" echo WARNING: pdftoppm path differs, poppler may need adjustment
echo OK: poppler downloaded
:poppler_done

REM --- Step 4e: LibreOffice (NOT bundled) ---
REM LibreOffice is intentionally NOT bundled (~350MB; msiexec extraction is
REM fragile in CI). docx/pptx creation and editing work without it; only
REM rendering to image preview needs it. Users who want rendering install
REM LibreOffice separately from https://www.libreoffice.org/

REM --- Step 5: Build pilotdeckui ---
if %SKIP_BUILD%==0 (
    echo.
    echo [5] Building pilotdeckui ^(vite^)...
    cd /d "%UI_DIR%"
    call npx vite build
    if errorlevel 1 (
        echo ERROR: vite build failed
        exit /b 1
    )
    echo OK
) else (
    echo [5] Skipping builds ^(--skip-build^)
    goto :skip_builds
)

REM --- Step 6: Build memory-core + pilotdeck-main ---
echo.
echo [6] Building memory-core + pilotdeck-main ^(tsc^)...
cd /d "%MEMORY_DIR%"
if exist lib rd /s /q lib
call npx tsc -p tsconfig.json
if errorlevel 1 (
    echo ERROR: memory-core tsc build failed
    exit /b 1
)
cd /d "%REPO_ROOT%"
call npx tsc -p tsconfig.json
if errorlevel 1 (
    echo ERROR: tsc build failed
    exit /b 1
)
mkdir dist\src\extension\plugins 2>nul
xcopy /E /I /Y src\extension\plugins\builtin dist\src\extension\plugins\builtin >nul
echo OK

REM --- Step 7: Create bundle tars ---
echo.
echo [7] Creating bundle tars...

cd /d "%UI_DIR%"
tar cf "%RESOURCES%\pilotdeckui-bundle.tar" ^
    --exclude=node_modules/.cache --exclude=node_modules/.bin ^
    --exclude=node_modules/typescript --exclude=node_modules/@types ^
    --exclude=node_modules/vite --exclude=node_modules/@vitejs ^
    --exclude=node_modules/rollup --exclude=node_modules/@rollup ^
    --exclude=node_modules/esbuild --exclude=node_modules/@esbuild ^
    --exclude=node_modules/eslint --exclude=node_modules/@eslint ^
    package.json server shared dist scripts node_modules
echo   pilotdeckui-bundle.tar OK

cd /d "%REPO_ROOT%"
tar cf "%RESOURCES%\pilotdeck-main-bundle.tar" ^
    --exclude=node_modules/.cache --exclude=node_modules/.bin ^
    --exclude=node_modules/typescript --exclude=node_modules/@types ^
    --exclude=node_modules/vite --exclude=node_modules/@vitejs ^
    --exclude=node_modules/rollup --exclude=node_modules/@rollup ^
    --exclude=node_modules/esbuild --exclude=node_modules/@esbuild ^
    --exclude=node_modules/eslint --exclude=node_modules/@eslint ^
    --exclude=apps --exclude=ui --exclude=old_ui ^
    --exclude=edgeclaw-memory-core --exclude=docs --exclude=tests ^
    --exclude=third-party --exclude=dist/tests --exclude=dist/scripts ^
    --exclude=.git --exclude=packages ^
    skills src dist/src scripts node_modules package.json tsconfig.json
echo   pilotdeck-main-bundle.tar OK

cd /d "%MEMORY_DIR%"
tar cf "%RESOURCES%\pilotdeck-memory-core-bundle.tar" ^
    package.json lib ui-source
echo   pilotdeck-memory-core-bundle.tar OK

:skip_builds

REM --- Step 8: Generate build-info.json ---
echo.
echo [8] Generating build-info.json...
cd /d "%REPO_ROOT%"
for /f "delims=" %%i in ('git rev-parse --short HEAD 2^>nul') do set "GIT_SHA=%%i"
for /f "delims=" %%i in ('git rev-parse HEAD 2^>nul') do set "GIT_FULL_SHA=%%i"
for /f "delims=" %%i in ('git rev-parse --abbrev-ref HEAD 2^>nul') do set "GIT_BRANCH=%%i"
for /f "delims=" %%i in ('node -e "console.log(require('./apps/desktop/package.json').version)"') do set "VERSION=%%i"

set "BUILD_DATE=%date:~0,4%-%date:~5,2%-%date:~8,2%"

mkdir "%DESKTOP_DIR%dist" 2>nul
echo {"version":"%VERSION%","gitSha":"%GIT_SHA%","gitFullSha":"%GIT_FULL_SHA%","gitBranch":"%GIT_BRANCH%","buildDate":"%BUILD_DATE%","mode":"win-build"} > "%DESKTOP_DIR%dist\build-info.json"
echo OK: v%VERSION% (%GIT_SHA%)

REM --- Step 9: Compile desktop TypeScript ---
echo.
echo [9] Compiling desktop TypeScript...
cd /d "%DESKTOP_DIR%"
call npx tsc
if errorlevel 1 (
    echo ERROR: desktop tsc failed
    exit /b 1
)
echo OK

REM --- Step 10: electron-builder ---
echo.
echo [10] Running electron-builder...
set CSC_IDENTITY_AUTO_DISCOVERY=false

if %X64_ONLY%==1 (
    call npx electron-builder --win --x64
) else (
    call npx electron-builder --win --x64 --arm64
)
if errorlevel 1 (
    echo ERROR: electron-builder failed
    exit /b 1
)

echo.
echo ========================================
echo  Build complete!
echo ========================================
echo.
echo Output:
dir /b "%DESKTOP_DIR%dist-electron\*.exe"
echo.
echo Location: %DESKTOP_DIR%dist-electron\
