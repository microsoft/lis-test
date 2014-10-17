lisa/ssh/readme.txt

The lisa/ssh directory holds the SSH keys used by the LISA framework.
Once you create your SSH keys to be used to communicate with the
Linux test VM, copy the keys to this directory.  You will also 
have to convert the private to a Putty Private Key (.ppk) to
allow the Putty utilities to use your SSH keys.

Some example SSH keys are provided and can be used with the LISA
framework.  The keys are:
	demo_id_rsa        - An OpenSSH private key
	demo_id_rsa.pub    - An OpenSSH public key
	demo_id_rsa.ppk    - An OpenSSH privated that has been converted
                             to the Putty Private Key (.ppk) format.
