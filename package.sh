#!/bin/bash
#
# Use this script to create the source package for
# use in creating an RPM package.

VERSION=$(cat VERSION)

# Create the directory structure we need
FNAME=mirth_snmp-$VERSION
DSTRUCT=/tmp/$FNAME

mkdir -p $DSTRUCT
cp -r bin $DSTRUCT
cp -r config $DSTRUCT

tar jcf $FNAME.tar.bz2 --directory /tmp $FNAME

rm -fr $DSTRUCT
