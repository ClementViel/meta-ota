include recipes-core/images/core-image-minimal.bb

LICENSE = "GPLv2"

IMAGE_FEATURES += "ssh-server-dropbear"
DISTRO_FEATURES_append += "wifi"
IMAGE_CLASS += "image_ota_part"
