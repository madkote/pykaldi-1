#!/bin/bash
# Copyright (c) 2013, Ondrej Platek, Ufal MFF UK <oplatek@ufal.mff.cuni.cz>
# based on egs/voxforge script created by  Vassil Panayotov Copyright 2012, Apache 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
# WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
# MERCHANTABLITY OR NON-INFRINGEMENT.
# See the Apache 2 License for the specific language governing permissions and
# limitations under the License. #

# The vystadial data are specific by having following marks in transcriptions
# _INHALE_
# _LAUGH_
# _EHM_HMM_
# _NOISE_
# _EHM_HMM_
# _SIL_

# renice 20 $$

source conf/train_conf.sh

locdata=data/local
locdict=$locdata/dict
local_lm=data/local/lm  # appending arpa in the script

mkdir -p $locdata

echo "=== Preparing the LM ..."
if [[ ! -z "$ARPA_MODEL" ]] ; then
    cp -f $ARPA_MODEL ${local_lm}_train_${LM_ORDER}.arpa
    echo "Using predefined LM in arpa format: ${ARPA_MODEL}"
else
    echo "=== Building LM of order ${LM_ORDER}..."
    cut -d' ' -f2- data/train/text | sed -e 's:^:<s> :' -e 's:$: </s>:' | \
        > $locdata/lm_train.txt

    ngram-count -text $locdata/lm_train.txt -order ${LM_ORDER} \
        -wbdiscount -interpolate -lm ${local_lm}_train_${LM_ORDER}.arpa
fi

# We assume that there no OOV in training data from pronounciation dictoinary
# For Czech it is true and for English we ignore the problem for now.
echo; echo "REMOVING OOV WORD FROM LANGUAGE MODEL"; echo
sed -i '/\<OOV\>/d' ${local_lm}_train_${LM_ORDER}.arpa


if [[ ! -z "$TEST_ZERO_GRAMS" ]]; then
    echo "=== Building ZERO GRAM for testing data..."
    cut -d' ' -f2- data/test/text | tr ' ' '\n' | \
      sort -u > $locdata/vocab-test.txt

    cp $locdata/vocab-test.txt ${local_lm}_test0.arpa
    echo "<unk>" >> ${local_lm}_test0.arpa
    echo "<s>" >> ${local_lm}_test0.arpa
    echo "</s>" >> ${local_lm}_test0.arpa
    python -c """
import math
with open('${local_lm}_test0.arpa', 'r+') as f:
    lines = f.readlines()
    p = math.log10(1/float(len(lines)));
    lines = ['%f\\t%s'%(p,l) for l in lines]
    f.seek(0); f.write('\\n\\\\data\\\\\\nngram  1=       %d\\n\\n\\\\1-grams:\\n' % len(lines))
    f.write(''.join(lines) + '\\\\end\\\\')
"""
fi


echo "=== Preparing the dictionary and phone lists..."

mkdir -p $locdict

if [ ! -z "${DICTIONARY}" ]; then
  echo; echo "Using predefined dictionary: ${DICTIONARY}"
  echo "Throwing away first 2 rows."; echo
  echo '</s>' > $locdata/vocab-full.txt
  tail -n +3 $DICTIONARY | cut -f 1 | \
    sort -u >> $locdata/vocab-full.txt
else
  cut -d' ' -f2- data/train/text | tr ' ' '\n' | \
      grep -v '_' | sort -u > $locdata/vocab-full.txt
fi

local/prepare_${data_lang}_transcription.sh $locdata $locdict

echo "--- Prepare nonsilence phone lists ..."
# We suppose only nonsilence_phones in lexicon right now
awk '{for(n=2;n<=NF;n++) { p[$n]=1; }} END{for(x in p) {print x}}' \
    $locdict/lexicon.txt | sort > $locdict/nonsilence_phones.txt

echo "--- Adding silence phones to lexicon ..."
echo "_SIL_ SIL" >> $locdict/lexicon.txt
echo "_EHM_HMM_ EHM" >> $locdict/lexicon.txt
echo "_INHALE_ INH" >> $locdict/lexicon.txt
echo "_LAUGH_ LAU" >> $locdict/lexicon.txt
echo "_NOISE_ NOI" >> $locdict/lexicon.txt

sort $locdict/lexicon.txt -o $locdict/lexicon.txt  # sort in place

echo "--- Prepare silence phone lists ..."
# TODO In previous versions the silence phones
# were in nonsilence phones
# and it was not so bad TODO
echo SIL > $locdict/silence_phones.txt
echo EHM >> $locdict/silence_phones.txt
echo INH >> $locdict/silence_phones.txt
echo LAU >> $locdict/silence_phones.txt
echo NOI >> $locdict/silence_phones.txt

echo SIL > $locdict/optional_silence.txt

# Some downstream scripts expect this file exists, even if empty
touch $locdict/extra_questions.txt

echo "*** Dictionary preparation finished!"