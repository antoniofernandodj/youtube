@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

rem O equivalente do Makefile para quem desenvolve NO Windows, onde nao ha make.
rem
rem A diferenca em relacao ao `make windows` (que compila do Linux) e que aqui o
rem MSVC e nativo: nao precisa de cargo-xwin nem de adicionar o target, porque o
rem target ja e o da maquina.
rem
rem     fazer build      compila em release
rem     fazer run        roda em debug
rem     fazer dist       monta dist\<app>-windows e o .zip
rem     fazer instalar   monta o pacote e instala em %LOCALAPPDATA%
rem     fazer limpar     apaga target\ e dist\
rem     fazer            esta ajuda

set "APP=youtube"
set "VIEWS=views"
set "RAIZ=%~dp0"
set "DIST=%RAIZ%dist\%APP%-windows"

rem `+crt-static` embute a CRT: sem isso o .exe exige o Visual C++
rem Redistributable na maquina de destino, e falha com uma caixa de erro que nao
rem diz qual DLL faltou.
set "RUSTFLAGS=-C target-feature=+crt-static"

if "%~1"==""         goto :ajuda
if /i "%~1"=="ajuda" goto :ajuda
if /i "%~1"=="help"  goto :ajuda
if /i "%~1"=="build" goto :build
if /i "%~1"=="run"   goto :run
if /i "%~1"=="dist"  goto :dist
if /i "%~1"=="instalar" goto :instalar
if /i "%~1"=="limpar"   goto :limpar

echo   Comando desconhecido: %~1
goto :ajuda

:ajuda
echo.
echo   %APP% - o que da para fazer aqui
echo.
echo     fazer build      compila em release
echo     fazer run        roda em modo debug
echo     fazer dist       monta o pacote e o .zip em dist\
echo     fazer instalar   monta o pacote e instala em %%LOCALAPPDATA%%
echo     fazer limpar     apaga target\ e dist\
echo.
echo   No Linux, o equivalente e o Makefile: make help
echo.
exit /b 0

:build
cargo build --release || exit /b 1
echo.
echo   Executavel: target\release\%APP%.exe
exit /b 0

:run
cargo run
exit /b %errorlevel%

:dist
call :build || exit /b 1
echo.
echo   Montando %DIST%
if exist "%DIST%" rmdir /s /q "%DIST%"
mkdir "%DIST%" 2>nul

copy /y "%RAIZ%target\release\%APP%.exe" "%DIST%\" >nul || goto :erro_copia

rem `views\` INTEIRO, nunca sub-pasta por sub-pasta: copiar item a item faz este
rem passo esquecer em silencio um diretorio novo.
robocopy "%RAIZ%%VIEWS%" "%DIST%\%VIEWS%" /E /NJH /NJS /NDL /NP >nul
if errorlevel 8 goto :erro_copia

rem O storage do glacier e estado da maquina de quem desenvolveu, nao do pacote.
for /d /r "%DIST%\%VIEWS%" %%d in (.glacier-storage) do (
    if exist "%%d" rmdir /s /q "%%d"
)

if exist "%RAIZ%packaging\windows\instalar.bat" ^
    copy /y "%RAIZ%packaging\windows\instalar.bat" "%DIST%\" >nul
if exist "%RAIZ%packaging\windows\desinstalar.bat" ^
    copy /y "%RAIZ%packaging\windows\desinstalar.bat" "%DIST%\" >nul
if exist "%RAIZ%packaging\windows\LEIA-ME.txt" ^
    copy /y "%RAIZ%packaging\windows\LEIA-ME.txt" "%DIST%\" >nul

rem A conferencia que o Makefile tambem faz: um pacote sem `views\` compila,
rem instala, abre - e mostra uma janela vazia na maquina de outra pessoa.
if not exist "%DIST%\%VIEWS%" (
    echo   ERRO: PACOTE INCOMPLETO - a pasta %VIEWS% nao foi copiada.
    exit /b 1
)
set /a N=0
for /r "%DIST%\%VIEWS%" %%f in (*) do set /a N+=1
if !N! LSS 1 (
    echo   ERRO: PACOTE INCOMPLETO - %VIEWS% ficou vazia.
    exit /b 1
)
echo   pacote ok - !N! arquivos de %VIEWS%\ empacotados

rem O tar do Windows 10+ compacta sem PowerShell; se faltar, o .zip e opcional.
where tar >nul 2>&1
if not errorlevel 1 (
    pushd "%RAIZ%dist"
    tar -a -c -f "%APP%-windows.zip" "%APP%-windows" 2>nul
    popd
    if exist "%RAIZ%dist\%APP%-windows.zip" echo   Pacote: dist\%APP%-windows.zip
) else (
    echo   ^(tar nao encontrado - o .zip nao foi gerado, a pasta esta pronta^)
)
echo.
echo   Pronto: %DIST%
exit /b 0

:instalar
call :dist || exit /b 1
if not exist "%DIST%\instalar.bat" (
    echo   ERRO: packaging\windows\instalar.bat nao existe.
    exit /b 1
)
pushd "%DIST%"
call instalar.bat
popd
exit /b 0

:limpar
cargo clean
if exist "%RAIZ%dist" rmdir /s /q "%RAIZ%dist"
echo   target\ e dist\ apagados.
exit /b 0

:erro_copia
echo   ERRO: falha ao copiar os arquivos para %DIST%.
exit /b 1
