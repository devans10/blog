+++
title = "Setting up a Python Project"
date = "2018-09-13T00:00:00Z"
draft = false
tags = ["python"]
+++
I have been writing Python code for probably close to 10 years.  The crazy part about this is that I am completely self-taught in Python didn't know any "right" way to do things.  Basically, as a Systems Administrator, I was writing shell scripts, and as I came upon problems that required some more advanced features, I would switch to writing in Python.  More specifically, as I needed to interact with both WebLogic and WebSphere, I had to write code using the Python/Jython libraries that shipped with those products.

Anyway, I was writing these more like Bash scripts then proper Python programming.  So, last week I was on vacation, and decided to take a Python  3 class on [Linux Academy](https://linuxacademy.com).  The first 2/3rds of the class I pretty much breezed through, as it was mainly review. The last part of the class was dedicated to properly setting up a project to write code using Test Driven Development.  Needless to say, I thought this was just the bee's knees.  Being basically self-taught, I never really knew what the proper way (yes, I know there are probably many "proper" ways) to set things up.  In addition, it also answered many questions I had about how to setup testing in code("Hi, I am Dave, and I am *NOT* a developer").  

I'm currently working on a project to build a benchmark test for a new NAS unit.  I want this benchmark process to mirror an important workflow we have for our NAS mount points. So it seemed like a great project to setup with this system.

I'm not going to do a ton of explanation on the steps below.  Mainly, this is just going to be a wiki (mainly for me) on what to run for each step to build a skeleton of a basic Python project.

### Installing Python

###### On CentOS 7
```bash
$ sudo su -
$ yum groupinstall -y "development tools"
$ yum install -y \
  libffi-devel \
  zlib-devel \
  bzip2-devel \
  openssl-devel \
  ncurses-devel \
  sqlite-devel \
  readline-devel \
  tk-devel \
  gdbm-devel \
  db4-devel \
  libpcap-devel \
  xz-devel \
  expat-devel

$ cd /usr/src
$ wget http://python.org/ftp/python/3.7.0/Python-3.7.0.tar.xz
$ tar xf Python-3.7.0.tar.xz
$ cd Python-3.7.0
$ ./configure --enable-optimizations
$ make altinstall
$ exit
```

Add ``/usr/local/bin`` to the``secure_path`` in the sudoers file

Update ``pip``
```bash
$ sudo pip3.7 install --upgrade pip
```


###### On Ubuntu 18.04
```bash
$ sudo su -
$ apt update -y
$ apt install -y \
  wget \
  build-essential \
  libssl-dev \
  zlib1g-dev \
  libbz2-dev \
  libreadline-dev \
  libsqlite3-dev \
  libncurses5-dev \
  libncursesw5-dev \
  xz-utils \
  libffi-dev \
  tk-dev

$ cd /usr/src
$ wget http://python.org/ftp/python/3.7.0/Python-3.7.0.tar.xz
$ tar xf Python-3.7.0.tar.xz
$ cd Python-3.7.0.tar.xz
$ ./configure --enable-optimizations
$ make altinstall
$ exit
```

Update ``pip``
```bash
$ sudo pip3.7 install --upgrade pip
```


### Setup virtualenv

```bash
$ pip3.7 install pipenv
$ mkdir nasbenchmark && cd nasbenchmark
$ pipenv install $(which python3.7)
$ git init
$ curl https://raw.githubusercontent.com/github/gitignore/master/Python.gitignore -o .gitignore
$ pipenv shell
```

### Create README

Create a README.rst file for the project.  A skeleton file is below.

```
project name
========

A Project Description

Preparing for Development
-------------------------

1. Ensure ``pip`` and ``pipenv`` are installed
2. Clone repository: ``git clone git@gitlab.com:example/projectname``
3. ``cd`` into repository
4. Fetch development dependencies ``make install``
5. Activate virtualenv: ``pipenv shell``

Usage
-----

Example:

::

    $ example run code

Running Tests
-------------

Run tests locally using ``make`` if virtualenv is active:

::

    $ make

If virtualenv isn’t active then use:

::

    $ pipenv run make
```

### Create Makefile and setup.py

setup.py:
```
from setuptools import setup, find_packages

with open('README.rst', encoding='UTF-8') as f:
    readme = f.read()

setup(
    name='projname',
    version='0.1.0',
    description='Description',
    long_description=readme,
    author='Dave Evans',
    author_email='dave@example.com',
    packages=find_packages('src'),
    package_dir={'': 'src'},
    install_requires=[],
    entry_points={
        'console_scripts': [
            'projname=projname.somepackage:main',
        ],
    }
)
```

Makefile:
```
.PHONY: default install test

default: test

install:
    pipenv install --dev --skip-lock

test:
    PYTHONPATH=./src pytest
```
Note: the spaces in front of the pipenv and PYTHONPATH have to be ``tabs``

### Setup pytest

Install pytest into virtualenv
```
$ pipenv install --dev pytest
```

```
$ mkdir -p src/projname tests
$ touch src/projname/__init__.py tests/.keep
```

Packages should go in ``src/projname``
Tests should go in ``tests/test_testname.py``


Thats it. You should now have a basic shell of a project that you can do test driven development in.  I can't take any credit for this.  For a much deeper dive into this, please sign up for [Linux Academy](https://linuxacademy.com) training.  It is well worth it. They have *TONS* of content for both beginners and experienced Linux users.


