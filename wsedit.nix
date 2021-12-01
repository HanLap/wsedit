{ mkDerivation, base, bytestring, charsetdetect-ae, data-default
, deepseq, directory, filepath, hashable, Hclip, lib, mtl, parsec
, pretty-show, process, safe, split, strict, transformers, unix
, vty
}:
mkDerivation {
  pname = "wsedit";
  version = "1.2.4.2";
  src = ./.;
  isLibrary = false;
  isExecutable = true;
  libraryHaskellDepends = [
    base bytestring charsetdetect-ae data-default deepseq directory
    filepath hashable Hclip mtl parsec pretty-show process safe split
    strict transformers unix vty
  ];
  executableHaskellDepends = [ base ];
  homepage = "https://github.com/LadyBoonami/wsedit";
  description = "A simple terminal source code editor";
  license = lib.licenses.bsd3;
}
