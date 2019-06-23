# Set-CustomAliases 

This command reads a CSV file and then defines powershell aliases based on the file contents

It is intended for use within the profile loader (either `$profile.AllUsersAllHosts` or `$profile.CurrentUserAllHosts`) so that the environment is configured with all of a user's shortcuts each time it is started

A sample `Alias.csv` is provided though the file name and location are not proscribed


## Usage

```
    .\Set-CustomAliases.ps1 Alias.csv [-Verbose]
```
By default the command does not show any output 

### Options
- **-Verbose** allows for troubleshooting in case things arent working as expected by writing as much information as it can to the console
- **-Force** if an alias already exists by the name specified, this option will force it to be replaced