// setup_portal.h
//
// First-time setup. When the board has no Wi-Fi saved, it creates its own
// hotspot (SETUP_AP_SSID) and serves a web page at http://192.168.4.1. The
// page lists the networks the board can see, asks for the Wi-Fi password,
// and asks for the broker's laptop name or IP and its login. On save, the
// board stores everything in flash and restarts to join the home network.

#ifndef SETUP_PORTAL_H
#define SETUP_PORTAL_H

// Runs the setup page. Never returns: it restarts the board after a save.
void setupPortalRun();

#endif // SETUP_PORTAL_H
