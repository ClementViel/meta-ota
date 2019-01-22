SUMMARY="ota scripts and files"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=5a96cefadfd9f9d956b2c3ec7bdde482"
SRC_URI = "file://ota.its \
			file://LICENSE \
			"



do_unpack_append() {
    bb.build.exec_func('do_copy_right', d)
}

do_copy_right() {

	cd ${DEVSHELL_STARTDIR}
	cd ..
	cp LICENSE ${DEVSHELL_STARTDIR}/LICENSE
}

do_install () {
	cp ${WORKDIR}/ota.its ${DEPLOY_DIR_IMAGE}/ota.its
}
