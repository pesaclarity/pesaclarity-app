"""Prints a SideStore/AltStore source for the unsigned iPhone test build.

Run by the iOS build workflow with VERSION, BUILD, MIN_OS, SIZE and IPA_URL
set from the built app. Testers add the source's address once; SideStore then
shows Update whenever a newer build is published.
"""

import json
import os
from datetime import datetime, timezone

SITE = "https://pesaclarity.github.io"

app = {
    "name": "Pesa Clarity",
    "bundleIdentifier": "com.pesaclarity.app",
    "developerName": "Pesa Clarity",
    "subtitle": "Your money, made clear",
    "localizedDescription": (
        "Free, ad-free and open source. Turns M-Pesa and bank messages into a "
        "clear daily plan, with everything kept on your phone. This is the "
        "test build: sign-in is off, and messages come in through Shortcuts."
    ),
    "iconURL": f"{SITE}/apple-touch-icon.png",
    "tintColor": "C8102E",
    "versions": [
        {
            "version": os.environ["VERSION"],
            "buildVersion": os.environ["BUILD"],
            "date": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "localizedDescription": "The newest test build from dev.",
            "downloadURL": os.environ["IPA_URL"],
            "size": int(os.environ["SIZE"]),
            "minOSVersion": os.environ["MIN_OS"],
        }
    ],
    "appPermissions": {"entitlements": [], "privacy": {}},
}

print(
    json.dumps(
        {
            "name": "Pesa Clarity",
            "identifier": "io.github.pesaclarity.source",
            "subtitle": "Test builds of Pesa Clarity for iPhone",
            "website": SITE,
            "iconURL": f"{SITE}/apple-touch-icon.png",
            "tintColor": "C8102E",
            "apps": [app],
            "news": [],
        },
        indent=2,
    )
)
