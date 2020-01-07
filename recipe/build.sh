#!/bin/bash

set -x

export CPPFLAGS="-I$PREFIX/include $CPPFLAGS"
export LDFLAGS="-L$PREFIX/lib $LDFLAGS"
export LD_LIBRARY_PATH="$PREFIX/lib:$LD_LIBRARY_PATH"
export CFLAGS="-g -O3 -fPIC $CFLAGS"

# Following is adapted from https://github.com/sagemath/sage

# Delete PDF documentation and misc TeX files
find doc \( \
         -name "*.bbl" \
      -o -name "*.blg" \
      -o -name "*.aux" \
      -o -name "*.dvi" \
      -o -name "*.idx" \
      -o -name "*.ilg" \
      -o -name "*.l*" \
      -o -name "*.m*" \
      -o -name "*.pdf" \
      -o -name "*.ind" \
      -o -name "*.toc" \
      \) -exec rm {} \;

shopt -s extglob

# Stuff that isn't GAP sources:
cd extern
rm -r !(Makefile.in)
cd ..

chmod +x configure

./configure \
    --prefix="$PREFIX" PREFIX="$PREFIX" \
    --with-gmp="$PREFIX" \
    CC="$CC" CXX="$CXX" CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS"

make

cd pkg

# Disable problematic packages. See https://github.com/conda-forge/gap-feedstock/pull/16
for GAP_PKG_NAME in kbmag cohomolo guava example ace xgap anupq polymakeinterface fplsa;
do
    PKG_DIR=`find . -maxdepth 1 -iname "$GAP_PKG_NAME-*" -type d`
    rm -rf $PKG_DIR
done

SEMIGROUPS_PKG_DIR=`find . -maxdepth 1 -iname "semigroups-*" -type d`
pushd $SEMIGROUPS_PKG_DIR/libsemigroups
  mv VERSION .VERSION
  sed -i.bak 's/-mavx//g' Makefile.am
  sed -i.bak 's/-march=native//g' Makefile.am
  sed -i.bak 's/-mavx//g' Makefile.in
  sed -i.bak 's/-march=native//g' Makefile.in
popd

sed -i.bak "s@./build-normaliz.sh@echo@g" ../bin/BuildPackages.sh
bash ../bin/BuildPackages.sh

# Build semigroups with external libsemigroups
# libsemigroups vendored and one from conda are ABI compatible
pushd $SEMIGROUPS_PKG_DIR
./configure --with-graproot=$SRC_DIR --with-external-libsemigroups
make
rm -rf src/libsemigroups
rm -rf bin/lib
if [[ "$target_platform" == "osx-64" ]]; then
    ${INSTALL_NAME_TOOL} -change ${SRC_DIR}/pkg/${SEMIGROUPS_PKG_DIR:2}/src/libsemigroups/../../bin/lib/libsemigroups.0.dylib @rpath/libplanarity.0.dylib bin/64/semigroups.so
fi
popd

# Remove planarity and use the one from conda
# planarity vendored and one from conda are ABI compatible
DIGRAPHS_PKG_DIR=`find . -maxdepth 1 -iname "digraphs-*" -type d`
rm -rf $DIGRAPHS_PKG_DIR/extern/edge-addition-planarity-suite-Version_3.0.0.5
rm -rf $DIGRAPHS_PKG_DIR/bin/lib
if [[ "$target_platform" == "osx-64" ]]; then
    ${INSTALL_NAME_TOOL} -change ${SRC_DIR}/pkg/${DIGRAPHS_PKG_DIR:2}/extern/edge-addition-planarity-suite-Version_3.0.0.5/../../bin/lib/libplanarity.0.dylib @rpath/libplanarity.0.dylib $DIGRAPHS_PKG_DIR/bin/64/digraphs.so
fi

# Print error logs
mkdir -p log
ls -al log
touch log/fail.log
cat log/fail.log
for file in log/*; do
  echo "--------------------------$file--------------------"
  cat $file
done
rm -rf log

for folder in *; do
  pushd $folder
  echo "GAP_PKG_NAME: $GAP_PKG_NAME"
  GAP_PKG_NAME=$(echo $folder | cut -d- -f1)
  load_output=$(../../bin/gap.sh -q -T <<< "LoadPackage(\"$GAP_PKG_NAME\");")
  [[ "${load_output}" == "true" || "${load_output:1}" == "true" ]] || echo "Loading fails"
  popd
done

