echo off
cd %VAR%
..\..\..\util\setconsole.exe /reset
echo.
echo Press 1 to play Ultima V - Warriors of Destiny
echo Press 2 to play Ultima V - Warriors of Destiny with Ultimapper5
echo Press 3 to play Ultima V - Warriors of Destiny (Upgrade)
echo Press 4 to play Ultima V - Warriors of Destiny (Upgrade) with Ultimapper5
echo.
..\..\..\util\choice /C:1234 /N Please Choose:

if errorlevel = 4 goto UM5u
if errorlevel = 3 goto dosboxu
if errorlevel = 2 goto UM5
if errorlevel = 1 goto dosbox

:dosbox
..\..\..\util\setconsole.exe /minimize
cd ..
".\emulators\dosbox\%dosbox%" -conf "%var%\dosbox.conf" -conf ".\emulators\dosbox\options.conf" -conf %conf% -noconsole -exit -nomenu
goto end

:dosboxu
".\emulators\dosbox\%dosbox%" -conf "%var%\dosbox2.conf" -conf ".\emulators\dosbox\options.conf" -conf %conf% -noconsole -exit -nomenu
goto end

:UM5
start .\util\Ultimapper5\Ultimapper_5 1
".\emulators\dosbox\%dosbox%" -conf "%var%\dosbox.conf" -conf ".\emulators\dosbox\options.conf" -conf ".\emulators\dosbox\gbc.conf" -noconsole -exit -nomenu
goto end

:UM5u
start .\util\Ultimapper5\Ultimapper_5 2
".\emulators\dosbox\%dosbox%" -conf "%var%\dosbox2.conf" -conf ".\emulators\dosbox\options.conf" -conf ".\emulators\dosbox\gbc.conf" -noconsole -exit -nomenu
goto end
