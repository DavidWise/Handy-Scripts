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

