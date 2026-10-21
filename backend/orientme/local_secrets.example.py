"""Optional template for orientme/local_secrets.py (git-ignored).

The preferred way to set the settings password is the SETTINGS_EDIT_PASSWORD
environment variable (see ../../.env.example). If you would rather keep it in
a local file, copy this file to local_secrets.py and set a real value. Never
commit the real file.
"""

# Password asked for before anything on the Settings page can be changed.
# While this is empty (and the environment variable is unset), Settings cannot
# be changed at all (it fails closed).
SETTINGS_EDIT_PASSWORD = ""
