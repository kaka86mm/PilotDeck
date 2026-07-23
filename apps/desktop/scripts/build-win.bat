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
    REM pnpm default (isolated) linker is REQUIRED: vite.config.js resolves
    REM react/react-dom from ui/node_modules via symlinks; node-linker=hoisted
    REM breaks this. The symlinks are dereferenced at tar time (-h flag, see
    REM step 7) so the final bundle has real files, not broken links.
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
python.exe -m pip install --quiet python-docx "lxml>=5.2,<7" openpyxl python-pptx pypdf pdfplumber reportlab PyMuPDF Pillow requests
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

REM --- Step 4e: Download GitHub CLI (gh) for Windows ---
if exist "%RESOURCES%\gh-bin\gh.exe" goto :gh_done
echo.
echo [4e] Downloading GitHub CLI for Windows x64...
mkdir "%RESOURCES%\gh-bin" 2>nul
cd /d "%RESOURCES%\gh-bin"
curl -fsSL -o gh.zip https://github.com/cli/cli/releases/download/v2.67.0/gh_2.67.0_windows_amd64.zip
if errorlevel 1 (
    echo WARNING: GitHub CLI download failed, github skill may not work
    goto :gh_skip
)
tar xf gh.zip
move "gh_2.67.0_windows_amd64\bin\gh.exe" gh.exe >nul 2>nul
rd /s /q "gh_2.67.0_windows_amd64" 2>nul
del gh.zip
if exist gh.exe (echo OK: gh downloaded) else (echo WARNING: gh.exe not found)
:gh_skip
:gh_done

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

REM --- Step 6b: Build symlink-free production node_modules (staging) ---
REM CRITICAL FIX: pnpm's isolated linker creates symlinks/junctions into a
REM .pnpm store. Windows bsdtar cannot reliably preserve these through
REM NSIS install + user-side extraction, causing ERR_MODULE_NOT_FOUND at
REM gateway startup. We build SEPARATE flat node_modules via npm install
REM --production (zero symlinks, real directories) in a staging directory,
REM and pack THAT. The pnpm install (step 2) is only for building.
echo.
echo [6b] Building flat production node_modules (staging)...
set "STAGE=%DESKTOP_DIR%stage"
if exist "%STAGE%" rd /s /q "%STAGE%"
mkdir "%STAGE%\pilotdeck-main" "%STAGE%\pilotdeckui" 2>nul

REM --- Root production deps (flat, no symlinks) ---
copy /Y "%REPO_ROOT%package.json" "%STAGE%\pilotdeck-main\package.json" >nul
cd /d "%STAGE%\pilotdeck-main"
call npm install --production --ignore-scripts --no-audit --no-fund
if errorlevel 1 (
    echo ERROR: staging root npm install failed
    exit /b 1
)
echo   root staging node_modules OK

REM Remove broken edgeclaw-memory-core symlink from staging.
REM npm creates it as a file: dep symlink (-> ../src/context/memory/...)
REM but that target does NOT exist in the staging dir. The runtime
REM recreates this link at startup, but only if it does not already
REM exist. A broken symlink in the bundle causes the ESM resolver
REM (DefaultResolve) to fail at gateway startup.
REM Use rmdir which removes the junction/symlink itself (not target).
if exist "%STAGE%\pilotdeck-main\node_modules\edgeclaw-memory-core" (
    rmdir /q "%STAGE%\pilotdeck-main\node_modules\edgeclaw-memory-core" 2>nul
)
REM Also try del in case it is a file symlink, not a dir junction
del /q "%STAGE%\pilotdeck-main\node_modules\edgeclaw-memory-core" 2>nul
echo   cleaned edgeclaw-memory-core symlink from staging

REM --- UI production deps (flat, no symlinks) ---
copy /Y "%UI_DIR%\package.json" "%STAGE%\pilotdeckui\package.json" >nul
cd /d "%STAGE%\pilotdeckui"
call npm install --production --ignore-scripts --no-audit --no-fund
if errorlevel 1 (
    echo ERROR: staging ui npm install failed
    exit /b 1
)
echo   ui staging node_modules OK

REM --- Step 6c: Rebuild native modules in staging for bundled Node ABI ---
REM npm install --ignore-scripts skipped native compilation. We must rebuild
REM better-sqlite3, node-pty, bcrypt (ui) and sharp (root) for the bundled
REM Node v22.14.0 ABI, otherwise they crash at runtime with no .node binary.
echo.
echo [6c] Rebuilding native modules in staging...
cd /d "%STAGE%\pilotdeck-main"
"%RESOURCES%\node-bin\node.exe" "%NPM_CLI%" rebuild sharp 2>nul
cd /d "%STAGE%\pilotdeckui"
"%RESOURCES%\node-bin\node.exe" "%NPM_CLI%" rebuild better-sqlite3 node-pty bcrypt
if errorlevel 1 (
    echo WARNING: some native modules failed to rebuild, office/terminal features may not work
)
echo   native modules rebuilt

REM --- Step 6d: Install skill runtime node_modules (pptx, spreadsheets) ---
REM These skills have runtime/package.json with JS deps (pptxgenjs, exceljs,
REM sharp, etc.) that must be installed and bundled. Without them the skills
REM fail with "Cannot find module".
echo.
echo [6d] Installing skill runtime node_modules...
cd /d "%REPO_ROOT%"
"%RESOURCES%\node-bin\node.exe" "%NPM_CLI%" install --prefix "skills\pptx\runtime" --omit=dev --no-audit --no-fund
if errorlevel 1 (
    echo WARNING: pptx skill node_modules install failed
)
"%RESOURCES%\node-bin\node.exe" "%NPM_CLI%" install --prefix "skills\spreadsheets\runtime" --omit=dev --no-audit --no-fund
if errorlevel 1 (
    echo WARNING: spreadsheets skill node_modules install failed
)
echo   skill runtime node_modules installed

REM --- Step 7: Create bundle tars (from staging, no symlinks) ---
echo.
echo [7] Creating bundle tars...

REM pilotdeckui-bundle: ui server code (from source) + flat ui node_modules (staging)
REM We pack in two steps: first tar the staging node_modules, then use a temp
REM dir to combine with ui source files, then tar czf the combined set.
mkdir "%STAGE%\pilotdeckui-build\server" "%STAGE%\pilotdeckui-build\shared" "%STAGE%\pilotdeckui-build\dist" "%STAGE%\pilotdeckui-build\scripts" 2>nul
xcopy /E /I /Y "%UI_DIR%\server" "%STAGE%\pilotdeckui-build\server" >nul 2>nul
xcopy /E /I /Y "%UI_DIR%\shared" "%STAGE%\pilotdeckui-build\shared" >nul 2>nul
xcopy /E /I /Y "%UI_DIR%\dist" "%STAGE%\pilotdeckui-build\dist" >nul 2>nul
xcopy /E /I /Y "%UI_DIR%\scripts" "%STAGE%\pilotdeckui-build\scripts" >nul 2>nul
copy /Y "%UI_DIR%\package.json" "%STAGE%\pilotdeckui-build\package.json" >nul
move /Y "%STAGE%\pilotdeckui\node_modules" "%STAGE%\pilotdeckui-build\node_modules" >nul
cd /d "%STAGE%\pilotdeckui-build"
tar czf "%RESOURCES%\pilotdeckui-bundle.tar.gz" ^
    --exclude=node_modules/.cache --exclude=node_modules/.bin ^
    --exclude=node_modules/.pnpm --exclude=node_modules/.modules.yaml ^
    package.json server shared dist scripts node_modules
echo   pilotdeckui-bundle.tar.gz OK

REM pilotdeck-main-bundle: compiled dist + skills + src + flat root node_modules
mkdir "%STAGE%\pilotdeck-main-build\skills" "%STAGE%\pilotdeck-main-build\src" "%STAGE%\pilotdeck-main-build\dist" "%STAGE%\pilotdeck-main-build\scripts" 2>nul
xcopy /E /I /Y "%REPO_ROOT%skills" "%STAGE%\pilotdeck-main-build\skills" >nul
xcopy /E /I /Y "%REPO_ROOT%src" "%STAGE%\pilotdeck-main-build\src" >nul 2>nul
xcopy /E /I /Y "%REPO_ROOT%dist\src" "%STAGE%\pilotdeck-main-build\dist\src" >nul
xcopy /E /I /Y "%REPO_ROOT%scripts" "%STAGE%\pilotdeck-main-build\scripts" >nul 2>nul
copy /Y "%REPO_ROOT%package.json" "%STAGE%\pilotdeck-main-build\package.json" >nul
copy /Y "%REPO_ROOT%tsconfig.json" "%STAGE%\pilotdeck-main-build\tsconfig.json" >nul 2>nul
move /Y "%STAGE%\pilotdeck-main\node_modules" "%STAGE%\pilotdeck-main-build\node_modules" >nul
cd /d "%STAGE%\pilotdeck-main-build"
tar czf "%RESOURCES%\pilotdeck-main-bundle.tar.gz" ^
    --exclude=node_modules/.cache --exclude=node_modules/.bin ^
    --exclude=node_modules/.pnpm --exclude=node_modules/.modules.yaml ^
    --exclude=apps --exclude=ui --exclude=old_ui ^
    --exclude=edgeclaw-memory-core --exclude=docs --exclude=tests ^
    --exclude=third-party --exclude=dist\tests --exclude=dist\scripts ^
    --exclude=.git --exclude=packages ^
    --exclude=skills/pptx/runtime/node_modules ^
    --exclude=skills/spreadsheets/runtime/node_modules ^
    skills src dist scripts node_modules package.json tsconfig.json
echo   pilotdeck-main-bundle.tar.gz OK

REM pilotdeck-memory-core-bundle: compiled lib
cd /d "%MEMORY_DIR%"
tar czf "%RESOURCES%\pilotdeck-memory-core-bundle.tar.gz" ^
    package.json lib ui-source
echo   pilotdeck-memory-core-bundle.tar.gz OK

REM Skill runtime node_modules (separate tars to avoid bsdtar dropping skills)
cd /d "%REPO_ROOT%"
if exist "skills\pptx\runtime\node_modules" (
    cd /d "%REPO_ROOT%\skills\pptx\runtime"
    tar czf "%RESOURCES%\pptx-runtime-deps.tar.gz" node_modules package.json
    echo   pptx-runtime-deps.tar.gz OK
)
cd /d "%REPO_ROOT%"
if exist "skills\spreadsheets\runtime\node_modules" (
    cd /d "%REPO_ROOT%\skills\spreadsheets\runtime"
    tar czf "%RESOURCES%\spreadsheets-runtime-deps.tar.gz" node_modules package.json
    echo   spreadsheets-runtime-deps.tar.gz OK
)

REM Clean up staging to save disk
cd /d "%DESKTOP_DIR%"
rd /s /q "%STAGE%" 2>nul

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
