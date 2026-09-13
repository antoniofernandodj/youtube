@echo off
setlocal
chcp 65001 >nul

rem Desinstalador do youtube. Remove o programa e o atalho; NAO remove o
rem config.ini nem as obras geradas - apagar o trabalho de alguem por tabela
rem seria pior que deixar um diretorio para tras. Os dois caminhos ficam
rem impressos no fim, para quem quiser apagar a mao.

set "APP=youtube"
set "DESTINO=%LOCALAPPDATA%\Programs\%APP%"
set "MENU=%APPDATA%\Microsoft\Windows\Start Menu\Programs"

tasklist /fi "imagename eq %APP%.exe" 2>nul | find /i "%APP%.exe" >nul
if not errorlevel 1 (
    echo   ERRO: o %APP% esta aberto. Feche-o e rode de novo.
    pause
    exit /b 1
)

if exist "%MENU%\%APP%.lnk" del "%MENU%\%APP%.lnk"
if exist "%DESTINO%" rmdir /s /q "%DESTINO%"

echo.
echo   %APP% removido.
echo.
echo   Ficaram no disco, de proposito:
echo     configuracao : %%APPDATA%%\%APP%\config.ini
echo     obras geradas: a pasta 'saidas' de onde voce rodou o app
echo.
pause
