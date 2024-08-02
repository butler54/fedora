# Initial secureboot and nvidia driver setup  

There is a lot of garbage out there. This is based on my experience as to what should work.

1. Follow the secure boot instructions [here](https://rpmfusion.org/Howto/Secure%20Boot?highlight=%28%5CbCategoryHowto%5Cb%29)

2. Also make sure you read the instructions at /usr/share/doc/akmods/README.secureboot

3. Check that secure boot is configured by using `sudo bootctl`

4. If is is not check your UEFI bios settings. the ASUS / Gigabyte setup had secure boot enabled in 'setup mode' which did not enforce secure boot (aka useless). 
   1. Toggling secure boot on and off / standard to custom seemed to trigger an enforced mode

5. Once booted bootctl is reporting a secure boot, check your MOK is enrolled (`sudo mokutil --test-key /etc/pki/akmods/certs/public_key.der`)

6. Follow the nvidia install instructions [here](https://rpmfusion.org/Howto/NVIDIA?highlight=%28%5CbCategoryHowto%5Cb%29)

7. When installing ensure akmods finishes compiling, `top` should work, before rebooting.

8. This is when all hell broke loose. So not sure of the actions that may have had impact. 
   9. Use recovery mode for testing which will load the opensource driver.

9. `sudo akmods --force --rebuild; dracut --regenerate --all` to force a rebuild of the modules

10. sudo vi /etc/default grub and add `nomodeset` to the GRUB_CMDLINE_LINUX line

11. `sudo grub2-mkconfig -o /etc/grub2.cfg`




