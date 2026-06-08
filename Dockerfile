FROM mcr.microsoft.com/windows/servercore:ltsc2022
RUN powershell -Command New-Item -ItemType Directory -Path C:\scripts -Force
COPY Find-StalePasswords.ps1 C:\scripts\
CMD ["powershell.exe", "-File", "C:\\scripts\\Find-StalePasswords.ps1"]
