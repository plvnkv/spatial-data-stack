import os

from geonode.settings import *  # noqa: F403

SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
OAUTH2_PROVIDER = {  # noqa: F405
    **OAUTH2_PROVIDER,  # noqa: F405
    "OIDC_RSA_PRIVATE_KEY": os.environ["OIDC_RSA_PRIVATE_KEY"],
}
