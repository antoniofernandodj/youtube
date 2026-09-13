@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

rem Instalador do youtube para Windows.
rem
rem Instala em %LOCALAPPDATA%, nao em "Program Files", de proposito: escrever em
rem Program Files exige elevacao, e um app de usuario nao precisa de admin so
rem para ser instalado. O atalho no menu Iniciar tambem e o do usuario.
rem
rem Copia o `views\` junto porque o app le os templates, os estilos e os scripts
rem Luau em runtime: sem essa pasta ao lado do .exe, a janela abre vazia.

set "APP=youtube"
set "DESTINO=%LOCALAPPDATA%\Programs\%APP%"
set "ORIGEM=%~dp0"
set "MENU=%APPDATA%\Microsoft\Windows\Start Menu\Programs"

echo.
echo   Instalando %APP%
echo   de : %ORIGEM%
echo   em : %DESTINO%
echo.

if not exist "%ORIGEM%%APP%.exe" (
    echo   ERRO: %APP%.exe nao esta nesta pasta.
    echo   Descompacte o .zip inteiro antes de rodar o instalador.
    goto :erro
)
if not exist "%ORIGEM%views" (
    echo   ERRO: a pasta 'views' nao esta nesta pasta - pacote incompleto.
    echo   Descompacte o .zip inteiro antes de rodar o instalador.
    goto :erro
)

rem Uma instalacao anterior pode estar aberta: copiar por cima de um .exe em uso
rem falha com "acesso negado", e o robocopy segue em frente sem dizer o que houve.
tasklist /fi "imagename eq %APP%.exe" 2>nul | find /i "%APP%.exe" >nul
if not errorlevel 1 (
    echo   ERRO: o %APP% esta aberto. Feche-o e rode de novo.
    goto :erro
)

if not exist "%DESTINO%" mkdir "%DESTINO%" 2>nul
if not exist "%DESTINO%" (
    echo   ERRO: nao consegui criar %DESTINO%
    goto :erro
)

rem /MIR espelha: um `views\` que perdeu um arquivo entre versoes nao fica para tras.
rem O robocopy usa codigos de saida < 8 para sucesso, entao o teste nao e o usual.
robocopy "%ORIGEM%views" "%DESTINO%\views" /MIR /NJH /NJS /NDL /NP >nul
if errorlevel 8 goto :erro_copia
copy /y "%ORIGEM%%APP%.exe" "%DESTINO%\" >nul
if errorlevel 1 goto :erro_copia
if exist "%ORIGEM%LEIA-ME.txt" copy /y "%ORIGEM%LEIA-ME.txt" "%DESTINO%\" >nul
if exist "%ORIGEM%desinstalar.bat" copy /y "%ORIGEM%desinstalar.bat" "%DESTINO%\" >nul

rem Atalho no menu Iniciar. "WorkingDirectory" e o que faz o app achar o `views\`
rem quando aberto pelo menu em vez de por duplo-clique na pasta: o app resolve
rem `views\` contra o diretorio de trabalho.
set "VBS=%TEMP%\%APP%-atalho.vbs"
> "%VBS%" echo Set s = CreateObject("WScript.Shell")
>>"%VBS%" echo Set a = s.CreateShortcut("%MENU%\%APP%.lnk")
>>"%VBS%" echo a.TargetPath = "%DESTINO%\%APP%.exe"
>>"%VBS%" echo a.WorkingDirectory = "%DESTINO%"
>>"%VBS%" echo a.Description = "Youtube"
>>"%VBS%" echo a.Save
cscript //nologo "%VBS%" >nul 2>&1
del "%VBS%" >nul 2>&1

echo   Pronto.
echo.
echo   Instalado em    : %DESTINO%
echo   Menu Iniciar    : %APP%
echo   Configuracao    : %%APPDATA%%\%APP%\config.ini
echo.
echo   A chave da API pode ser colada na tela inicial, em "ajustes" - ela fica
echo   gravada no config.ini acima e vale nas proximas vezes.
echo.
pause
exit /b 0

:erro_copia
echo   ERRO: falha ao copiar os arquivos para %DESTINO%.
:erro
echo.
pause
exit /b 1
