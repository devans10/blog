+++
title = "My New Favorite Tool... ncdu"
date = "2018-08-29T00:00:00Z"
draft = false
tags = ["tools", "ncdu"]
+++

So today I found my new favorite command line tool, ncdu.  This is a ncurses disk utilization tool that is great for finding what is filling up your file systems.  Especially on servers that do not have a graphical interface.

If you are like me, when I get file system alerts, it was an endless string of 'du -h --max-depth=1' commands. I would have to re-run that command as I drilled down through the directory structure.  With ncdu, the scan is performed once, and you can drill down through the directories within an ncurses interface.  

The tool has been packaged for most major distributions, and the source can be found on the [project site](https://dev.yorhel.nl/ncdu)

Its pretty simple to run. Once scan is complete, you can drill down to any of the directories.

![ncdu](/img/ncdu.jpeg)

Here are the examples from the man page.

#### EXAMPLES

> To scan and browse the directory you're currently in, all you need is a simple:
```
  ncdu
```
> If you want to scan a full filesystem, your root filesystem, for example, then you'll want to use -x:
```
  ncdu -x /
```
> Since scanning a large directory may take a while, you can scan a directory and export the results for later viewing:
```
  ncdu -1xo- / | gzip >export.gz
  # ...some time later:
  zcat export.gz | ncdu -f-
```
> To export from a cron job, make sure to replace -1 with -0 to suppress any unnecessary output.

> You can also export a directory and browse it once scanning is done:
```
  ncdu -o- | tee export.file | ./ncdu -f-
```
> The same is possible with gzip compression, but is a bit kludgey:
```
  ncdu -o- | gzip | tee export.gz | gunzip | ./ncdu -f-
```
> To scan a system remotely, but browse through the files locally:
```
  ssh -C user@system ncdu -o- / | ./ncdu -f-
```
> The -C option to ssh enables compression, which will be very useful over slow links. Remote scanning and local viewing has two major advantages when compared to running ncdu directly on the remote system: You can browse through the scanned directory on the local system without any network latency, and ncdu does not keep the entire directory structure in memory when exporting, so you won't consume much memory on the remote system.
