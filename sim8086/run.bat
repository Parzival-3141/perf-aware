@echo off

pushd %~dp0

if [%1] == [] goto :USAGE

set LISTINGS=..\computer_enhance\perfaware\part1

set TARGET=%1

for /f %%i in ('where /R %LISTINGS% listing_%1_*.') do set TARGET=%%i

if not exist %TARGET% (
	echo ERROR: %TARGET% doesn't exist!
	goto :USAGE
)

if [%2] == [] (
	echo Compiling... 1>&2
	zig build run -- %TARGET%
	goto :EXIT
)

if %2 == -test (
	set TEST=.\tests\listing-%1-test
	echo Compiling... 1>&2
	: zig build run -- %TARGET% > %TEST%.asm
	zig build
	echo Running... 1>&2
	zig-out\bin\sim8086 %TARGET% > %TEST%.asm
	echo Assembling %TEST%.asm... 1>&2
	nasm %TEST%.asm
	comp %TEST% %TARGET% /A /L /C /M
) else goto :USAGE

goto :EXIT

:USAGE
echo Usage:
echo.	run.bat ^<listing-number^> [-test]
echo.	^(listing-number must be 4 digits long ^(e.g. 0039^)^)
echo.
echo Options:	
echo.	-test	 Runs the output through NASM and compares with the listing binary


:EXIT
popd
exit /B

