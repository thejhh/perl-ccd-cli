
Perl CLI client for CCD server
==============================

1. SUMMARY
----------

ccd-client is CLI client for Sendanor's Control Center Daemon.

Users can be use it to edit their data in our system.

Intented people using this software are:

* Clients editing their own data directly
* ISPs editing clients data on behalf of them
* Resellers editing clients data on behalf of them

User interface is the same no matter who is using the software.

We plan to include web based client sometime in the future.

3. INSTALLATION
------------

3.1. INSTALLATION REQUIREMENTS
------------------------------

Packages needed (Debian names):

  libxml-simple-perl libwww-perl perl-modules libcrypt-ssleay-perl

3.2. INSTALLATION FROM SUBVERSION
---------------------------------

$ svn checkout https://svn.sendanor.fi/svn/sendanor/projects/ccd/client/trunk ccd-client
$ cd ccd-client

3.3. INSTALLATION WITH WGET
---------------------------

$ wget https://svn.sendanor.fi/svn/sendanor/projects/ccd/client/trunk/ccd-client.pl

4. EXAMPLES
-----------

$ ./ccd-client.pl help
USAGE: ccd COMMAND [NAME=VALUE ...]

Available commands:
  help
  activate account
  create account
  dummy
  login
  logout
  register client
  switch client
  show client

See also: help COMMAND

$ ./ccd-client.pl create account username="yritys@example.com"
username: yritys@example.com
password: XYsw3iNU
realname:
Account created successfully.
Email has been sent with instructions how to activate this account.

$ ./ccd-client.pl activate account code=FBDKI3MngTgqkyxGzzT8z1XpdcoFmwEP
Account activated successfully.

$ ./ccd-client.pl login username="yritys@example.com" password="XYsw3iNU"
Login successful as yritys@example.com (#1001).

$ ./ccd-client.pl switch client
Switched to client <yritys@example.com> (#1234)

$ ./ccd-client.pl show client
client_id: 1234
campaign_id: 0
updated: Wed May 06 2009 15:55:53 GMT+0300 (EEST)
creation: Thu Jan 01 1970 01:59:59 GMT+0200 (EET)
date: Thu Jan 01 1970 01:59:59 GMT+0200 (EET)
termination_date: Thu Jan 01 1970 01:59:59 GMT+0200 (EET)
company: Example Oy
company_code: 1234567-0
firstname: Matti
lastname: Meikalainen
address: Kiilakiventie 1
postcode: 90250
postname: OULU
email: yritys@example.com
phone: +358401234567
mobile:
fax:
send_email: 1
send_post: 0
is_terminated: 0

$ ./ccd-client.pl logout
You have logged out now.

