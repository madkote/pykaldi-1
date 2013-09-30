#!/bin/bash

# source the settings
. path.sh

mfcc_config=configs/mfcc.config

# temporary files
lattice=$decode_dir/lat.gz
mfccdir=$decode_dir/mfcc
feat_scp=$mfccdir/raw_mfcc.scp

mkdir -p $mfccdir
compute-mfcc-feats  --verbose=2 --config=$mfcc_config scp:$wav_scp \
  ark,scp:$mfccdir/raw_mfcc.ark,$feat_scp || exit 1;

gmm-latgen-faster --config=configs/decode.config  \
    --word-symbol-table=$wst $model $hclg \
    "ark,s,cs:copy-feats scp:$feat_scp ark:- | add-deltas  ark:- ark:- |" \
    "ark:|gzip - c > $lattice"

lattice-best-path --lm-scale=15 --word-symbol-table=$wst \
    "ark:gunzip -c $lattice|" ark,t:$gmm_latgen_faster_tra

cat $gmm_latgen_faster_tra | ./int2sym.pl -f 2- $wst > $gmm_latgen_faster_tra_txt

# reference is named based on wav_scp 
./build_reference.py $wav_scp $decode_dir  
reference=$decode_dir/`basename $wav_scp`.tra
compute-wer --text --mode=present ark:$reference ark,p:$gmm_latgen_faster_tra_txt

echo; echo "Reference"; echo
cat $reference
echo; echo "Decoded"; echo
cat $gmm_latgen_faster_tra_txt
