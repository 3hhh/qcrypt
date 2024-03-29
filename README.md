# qcrypt

qcrypt is a multilayer encryption tool for [Qubes OS](https://www.qubes-os.org/).

Each layer is decrypted inside a dedicated destination Virtual Machine (VM)/Qube until the final target VM can decrypt to the plaintext. The source VM doesn't decrypt anything itself.

It enables you to attach trusted storage to [Qubes OS](https://www.qubes-os.org/) VMs from untrusted storage backends (USB drive, cloud, ...).

Depending on the setup, it can mitigate attacks stemming from file system parsing bugs and can prevent compromised VMs from leaking their data with incorrect encryption. Header or encryption parsing bugs in [cryptsetup](https://gitlab.com/cryptsetup/cryptsetup/wikis/home) remain an issue, but their impact can be lessened manually (plain mode & mix different encryption algorithms).

Internally, qcrypt uses [cryptsetup](https://gitlab.com/cryptsetup/cryptsetup/wikis/home) in combination with standard [Qubes OS](https://www.qubes-os.org/) functionality (block device attachments).

Both qcrypt and qcryptd need to run in [Qubes OS](https://www.qubes-os.org/) dom0.

# qcryptd

qcryptd is a daemon to automate `qcrypt` for everyday usage.

It can detect device attachments and VMs being started and instantly attaches the configured qcrypt storage to the VM which was just started. This way it brings back the "plug & play feeling" for external storage that users are accustomed to from other operating systems.

# Example use cases

- slice a large cloud storage pool or USB pen drive into dedicated per-VM storage volumes
- confidentially share data across multiple Qubes OS machines
- bind persistent trusted storage to a disposable VM directory ("limited persistence")

## Table of contents

- [Installation](#installation)
  - [A word of caution](#a-word-of-caution)
- [Usage](#usage)
  - [qcrypt](#qcrypt)
  - [qcryptd](#qcryptd)
  - [But I want to use passwords?!](#but-i-want-to-use-passwords?!)
- [Uninstall](#uninstall)
- [Copyright](#copyright)

## Installation

1. Download [blib](https://github.com/3hhh/blib), copy it to dom0 and install it according to [its instructions](https://github.com/3hhh/blib#installation).
2. Download this repository with `git clone https://github.com/3hhh/qcrypt.git` or your browser and copy it to dom0.
3. Move the repository to a directory of your liking.
4. Symlink the `qcrypt` and `qcryptd` binaries into your dom0 `PATH` for convenience, e.g. to `/usr/bin/`.

### A word of caution

It is recommended to apply standard operational security practices during installation such as:

- Github SSL certificate checks
- Check the GPG commit signatures using `git log --pretty="format:%h %G? %GK %aN  %s"`. All of them should be good (G) signatures coming from the same key `(1533 C122 5C1B 41AF C46B 33EB) EB03 A691 DB2F 0833` (assuming you trust that key).
- Code review

You're installing something to dom0 after all.

## Usage

### qcrypt

`qcrypt luksInit` can be used to create new chains whose content is stored in encrypted form inside the source file in the respective source VM. The initial creation however happens in dom0; keys and the encrypted container are automatically passed to the respective VMs in the chain.  
**Warning**: Keep a backup of all encryption keys in the chain unless you're ready to lose your encrypted data.

Chains can then be opened via `qcrypt open` and their current attachment state can be observed with `qcrypt status`. Without command-line arguments, the latter also provides an overview of all currently active qcrypt chains.  
**Warning**: Unexpected shutdowns of VMs belonging to a chain may lead to data loss under extreme circumstances. In practice this rarely happens, but you should be prepared and have a backup available.

`qcrypt close` will let you close currently active chains.

Please consult `qcrypt help` after the installation for further details.

#### Examples

```
sudo qcrypt -a --size 3G --wd ~/qcrypt.tmp/ --bak ~/qcrypt.keys/ luksInit sys-usb /home/user/encrypted.lks secret.key mediator-vm work-vm
```

*Explanation:*
Autostart all required VMs and create a 3 Gigabyte container inside the `sys-usb` VM at `/home/user/encrypted.lks` (make sure you `sys-usb` has enough empty disk space). The encryption keys shall be named `secret.key` (you'll find two different keys with the same name inside `~/.qcrypt/keys/` in the `mediator-vm` as well as the `work-vm`), the first layer of decryption happen inside the `mediator-vm` and the second inside the `work-vm`. Only the `work-vm` is meant to see the plaintext data.
Moreover create a backup of all involved keys in dom0 inside the `~/qcrypt.keys/` directory and use `~/qcrypt.tmp/` to generate the encryption container and keys in dom0.
The current example has two destination VMs, but leaving out the `mediator-vm` can be appropriate - it depends on your threat model. Please consult `qcrypt help` after the installation for further explanations.

```
qcrypt --mp /mnt/ open sys-usb /home/user/encrypted.lks secret.key mediator-vm work-vm
```

*Explanation:*
Open the just created container and mount it to `/mnt/` inside the `work-vm`.

```
qcrypt status sys-usb /home/user/encrypted.lks secret.key mediator-vm work-vm
```

*Explanation:*
Double-check the current state of that chain. In particular a straightforward `qcrypt status` shows an overview of all currently open chains.

```
qcrypt close sys-usb /home/user/encrypted.lks secret.key mediator-vm work-vm
```

*Explanation:*
Close the chain. Please note that shutting down the `work-vm` without a close should be fine (you might have to use `qcrypt --force close` later on, which may shut down the `mediator-vm`), but shutting down the `mediator-vm` during the attachment is likely to leave your Qubes OS in a dreary state and will probably require you to restart the system.

### qcryptd

In order to manage new chains initialized with `qcrypt luksInit` or previously unmanaged chains with `qcryptd`, you'll have to create one ini configuration file per chain inside `/etc/qcryptd/default`. An example ini file can be found [here](https://github.com/3hhh/qcrypt/blob/master/conf/examples/ex01.ini).

It is then recommended to check that configuration with `qcryptd check`. Assuming your configuration was found to be correct, you can start the qcryptd service with `qcryptd start` and further control it with `qcryptd stop` and `qcryptd restart`. After configuration file changes it is recommended to do a `qcryptd -c restart`.

Also see `qcryptd help` for a more detailed description after the installation.

#### Example

Assuming that the `/home/user/encrypted.lks` file inside the `sys-usb` VM from the qcrypt example above was put on an external device `/dev/disk/by-uuid/id`, a minimal configuration file to automatically mount the container to the `work-vm` would look as follows:

```
source vm=sys-usb
source device=/dev/disk/by-uuid/id
source mount point=/mnt-id-dev
source file=/encrypted.lks
key=secret.key
destination vm 1=mediator-vm
destination vm 2=work-vm
destination mount point=/mnt
read-only=false
```

One could put that configuration e.g. inside the directory `/etc/qcryptd/example/med-work.ini` and could then start qcryptd with `qcryptd start example`, which will execute _all_ chain configurations found inside the `/etc/qcryptd/example/` directory.

Please keep in mind that the `mediator-vm` may be started or stopped by qcryptd at will. So it is highly recommended to use it only for the purpose of that single chain!

### But I want to use passwords?!

Both `qcrypt` and `qcryptd` support storing and retrieving your keys from a [blib](https://github.com/3hhh/blib) key store, which needs to be opened with exactly one password per boot session. Essentially it's just a password-protected luks container holding all your keys.

Of course, if you ever lose that container, your keys or forget your password, you lose all of your data. So make sure to always have a backup!

Also make sure _not_ to put key file backups inside a qcrypt container...

## Uninstall

1. Remove all symlinks that you created during the installation.
2. Remove the repository clone from dom0.
3. Uninstall [blib](https://github.com/3hhh/blib) according to [its instructions](https://github.com/3hhh/blib#uninstall).

## Copyright

© 2020 David Hobach
GPLv3

See `LICENSE` for details.
