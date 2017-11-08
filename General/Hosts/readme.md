# Hosts

As a web developer, I'm constantly developing different websites on my local machine and sometimes they expect certain host names for certain functionality.  THis is most easily accomplished by adding entries to the local ```hosts``` file.  

While this is a rather trivial task, it takes a few minutes each time I need to go in there.  This script makes it much easier

This also allows for the updating of local hosts files to be included as part of a pre/post build script


## **Note**: 
The ```hosts``` file can only be modified by a service running as Administrator (permission level, not account name!) and the script will check this prior to attempting to -Add or -Remove

---

## Usage

List all custom entries in your hosts files

```
.\hosts.ps1 -list

Host            Address    Comment
----            -------    -------
ifoo.local      127.0.0.15 Forced via command line
api.ifoo.local  127.0.0.1    local API reference
api.altfoo.com  127.0.0.1
altfoo.com      127.0.0.1
```

The result is shown as a simple table but the actual results are proper objects so that the output can then be used in another script

``` powershell
.\hosts.ps1 -list -full
```

Writes out the entire ```hosts``` file, including comments.  If with ```-full``` the output is simple strings

## Adding an Entry

```
.\hosts.ps1 -add [-hostname] yourname [-IPAddress yourIP] [-Comment "your comment"]

```

Adds an entry to the hosts file using the host name provided.  If no IP Address is provided, it will default to 127.0.0.1 (localhost).  You can also include a comment such as "added by AwesomeBuilder Uber Extreme 99.0" so that anyone looking at the hosts file will know why that entry is there

Both IPAddress and Comment are optional

## Removing an entry
```
.\hosts.ps1 -remove [-hostname] yourname [-IPAddress yourIP] [-Comment "your comment"]

```

this will remove all entries in the host file that match any of the values passed, including the comment so that batch scripts can better group their Adds and Removes.

**Caution**: *be very careful removing via IP Address as you can possibly clear out entries that you did not intend to remove simply because they point to the same IPAddress*
