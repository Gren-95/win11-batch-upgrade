# Windows 11 Batch Upgrade

[![License: MIT](https://img.shields.io/github/license/Gren-95/win11-batch-upgrade?color=blue)](LICENSE)
![Platform: Windows](https://img.shields.io/badge/platform-Windows-0078D6)
![Language: Batch](https://img.shields.io/badge/language-Batch-4D4D4D)
![Option 2: experimental](https://img.shields.io/badge/option%202-experimental-orange)
[![Last commit](https://img.shields.io/github/last-commit/Gren-95/win11-batch-upgrade)](https://github.com/Gren-95/win11-batch-upgrade/commits/main)
[![Stars](https://img.shields.io/github/stars/Gren-95/win11-batch-upgrade?style=flat)](https://github.com/Gren-95/win11-batch-upgrade/stargazers)

A batch script that starts the Windows 11 upgrade on many PCs at once from one admin
machine, using the Windows 11 Installation Assistant and PsExec. There is nothing to install on
the target PCs beforehand, and you get a summary and a log of which PCs succeeded or failed.

![Illustration of the script's menu and summary in a terminal window](assets/preview.svg)

*Illustration of the menu and summary, with example PC names.*

## What it does

It lists the computers and asks you to confirm, then handles each PC, one at a time:

1. Pings it and marks it as failed if it's offline.
2. Skips it if it's already on Windows 11 or the Installation Assistant is already running.
3. Marks it as failed if C: has too little free space, if there's no TPM 2.0, or if it starts in
   legacy BIOS mode. If these checks can't run, it warns and carries on.
4. Copies PC Health Check to `C:\` and installs it silently. A failure here is only a warning.
5. Copies the Installation Assistant to `C:\`, sends a message to the logged-on user, and starts
   the Assistant silently as SYSTEM.

At the start it asks what to do:

| Option | Behaviour | Switches |
| --- | --- | --- |
| **1 - Force restart** | The PC restarts by itself when ready. | `/QuietInstall /SkipEULA /AutoUpgrade /NoRestartUI` |
| **2 - User restarts** | Asks the Assistant to wait, so the upgrade finishes on the next restart. **Experimental, see below.** | The same, plus `/NoReboot` |
| **3 - Check status** | Changes nothing, and shows how far each PC is. | None |

### Status results

| Status | Meaning |
| --- | --- |
| `WINDOWS 11` | The upgrade is done. |
| `INSTALLING` | The Installation Assistant is running. |
| `WAITING FOR RESTART, OR FAILED` | The Assistant isn't running and setup files are on C:. The script can't tell these two cases apart. |
| `NOT STARTED, OR FAILED` | The Assistant isn't running and there are no setup files on C:. |
| `NO CONNECTION` | The PC answers ping, but PsExec couldn't read its Windows version. |
| `OFFLINE` | The PC doesn't answer ping. |

## Settings

These are at the top of the script:

| Setting | Default | Meaning |
| --- | --- | --- |
| `MINFREEGB` | `30` | Free space needed on C:, in GB. |
| `MSG1` | English text | Message shown to the logged-on user with option 1. |
| `MSG2` | English text | Message shown to the logged-on user with option 2. |

Don't use double quotes or exclamation marks in the messages.

## Warnings

- **Option 2 may still restart the PC by itself.** Microsoft doesn't document the Assistant's
  switches, and reports disagree on whether it can hold back the restart. Test on one spare PC
  and leave it for a few hours before using this on anyone's machine.
- **Options 1 and 2 can restart a PC with no warning at the time of the restart**, because the
  prompt is hidden and the Assistant runs as SYSTEM. The only warning is the message sent when
  the upgrade starts, which doesn't reach a user who logs on later. Unsaved work can be lost.
- **Running the script accepts the Windows license terms** on behalf of each PC (`/SkipEULA`).
  Make sure you are allowed to do that.

## Requirements

**On the admin PC**, put these in the same folder as `Win11_Batch_Upgrade.bat`. They are not
included in this repository. The script checks for them first and shows these links if any are
missing.

| File | Download |
| --- | --- |
| `PsExec64.exe` | [PSTools.zip](https://download.sysinternals.com/files/PSTools.zip) (take it out of the zip) |
| `Windows11InstallationAssistant.exe` | [Microsoft's Windows 11 download page](https://www.microsoft.com/software-download/windows11) |
| `WindowsPCHealthCheckSetup.msi` | [aka.ms/GetPCHealthCheckApp](https://aka.ms/GetPCHealthCheckApp) |

Run the script as a user who is a local administrator on the target PCs.

**On each target PC:**

- Replies to ping. A PC that blocks it is reported as offline.
- The `C$` admin share is reachable and PsExec can connect, which usually means File and Printer
  Sharing is allowed through the firewall.
- It meets the [Windows 11 system requirements](https://www.microsoft.com/windows/windows-11-specifications).
  The script checks free space, TPM 2.0 and UEFI only, not the CPU or anything else on that list.

## Usage

Give the computer names in one of three ways. The first one found wins:

```bat
rem 1. As arguments
Win11_Batch_Upgrade.bat PC01 PC02 PC03

rem 2. In computers.txt next to the script
Win11_Batch_Upgrade.bat

rem 3. No arguments and no computers.txt: the script asks you to type them
Win11_Batch_Upgrade.bat
```

`computers.txt` has one name per line, and lines starting with `#` are comments:

```text
# Office
PC01
PC02
```

Then choose an option at the prompt.

## Results

Options 1 and 2 end with a list of succeeded, skipped and failed PCs, and add the same results
to `Win11Upgrade_results.log` next to the script.

**"Upgrade started" only means the Assistant launched without an error**, not that the upgrade
finished or that the PC is ready to restart. Use option 3 to follow it up.

## Limitations

- PCs are handled one at a time.
- PCs already on any Windows 11 build are skipped, so this won't move them to a newer version.
- Running options 1 or 2 again on a PC that's waiting for its restart starts the Assistant again.
- `C:\Windows11InstallationAssistant.exe` and `C:\WindowsPCHealthCheckSetup.msi` stay on each PC.

## Holding back the restart reliably

Microsoft documents a `/NoReboot` switch for `setup.exe` from the Windows 11 ISO, in
[Windows Setup command-line options](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-command-line-options).
It only holds back the first restart, and this script doesn't use it, because that would mean
copying the full ISO to every PC.

## License

[MIT](LICENSE). PsExec, the Installation Assistant and PC Health Check are Microsoft software
under their own licenses.
