*Draft for owner review.* Phones, tablets and laptops are the machines most users carry, and they are the ones most likely to be lost, to run on battery, and to connect over wireless links. WinLab cannot give you a physical phone, so this lesson is concepts and procedure; the connectivity checks you can practise on the lab VMs.

## Device types and their parts

| Device | What distinguishes it |
|---|---|
| Laptop | Full desktop OS, battery, built-in display, keyboard, touchpad, usually replaceable RAM or storage |
| Tablet | Touch screen, mobile OS, battery, often non-serviceable |
| Smartphone | Cellular radio, SIM or eSIM, sensors, mobile OS |
| Wearable | Tiny battery, pairs with a phone over Bluetooth |

Laptop display problems are usually the panel, the cable (flickers when the lid moves), or the backlight (dim but visible image under a torch). Battery wear shows as shorter runtime and, in the extreme, a swollen case: stop using a swollen battery and dispose of it as hazardous waste.

## Connectivity

| Technology | Range and use | Quick checks |
|---|---|---|
| Wi-Fi (802.11) | Local network access; bands 2.4, 5 and 6 GHz | Is airplane mode on? Right network and password? Signal strength? |
| Bluetooth | Short range accessories and pairing | Paired, powered, in range, not paired to another device |
| Cellular (4G/5G) | Wide area data | SIM or eSIM active, plan, signal, APN |
| NFC | Centimetres; payments and tags | Enabled, case not blocking |
| VPN / hotspot | Tunnel to office; share a phone's connection | Credentials, split tunnelling, data limits |

The bottom-up network routine applies unchanged to a mobile device: link, address, gateway, name, port. A phone with a full-strength Wi-Fi icon and a "no internet" message usually has no valid address or no route, which is a layer-2 or layer-3 problem, not a signal problem.

## Management and security

Organisations enrol mobile devices in management (MDM) so they can enforce a passcode, encryption, and allowed apps, and wipe a lost device remotely. Corporate-owned and bring-your-own devices use different profiles: a personal device can hold a separate, managed work area. Keep the operating system updated, install apps only from the official store, and require a screen lock and encryption. Back up to the vendor's cloud or a managed backup; know how to restore to a new device.

## Troubleshooting routine

1. Restart: it clears many software faults.
2. Check settings: airplane mode, Wi-Fi, Bluetooth, battery saver, storage space.
3. Check updates and recently installed apps.
4. Isolate: a different network, a different charger and cable, safe mode.
5. Back up the user's data **before** a reset, and tell the user what a reset removes.

## Check yourself

1. A phone shows full Wi-Fi bars but cannot browse. Which layers do you check?
2. Why is a swollen battery an emergency?
3. What does a remote wipe do, and why must the device be enrolled first?
