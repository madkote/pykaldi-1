// -*- coding: utf-8 -*-
/* Copyright (c) 2013, Ondrej Platek, Ufal MFF UK <oplatek@ufal.mff.cuni.cz>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 * THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
 * WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
 * MERCHANTABLITY OR NON-INFRINGEMENT.
 * See the Apache 2 License for the specific language governing permissions and
 * limitations under the License. */
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <stdlib.h>
#include <iostream>
#include "online-python-gmm-decode-faster.h"

using namespace kaldi;

template<class FT> FT load_function(const char *nameFce, void *lib);
void fill_frame_random(unsigned char *frame, size_t size);
size_t next_frame(unsigned char * frame, size_t frame_len,
                  unsigned char *pcm, size_t pcm_position);
int main(int argc, char **argv);
void printHyp(int *word_ids, size_t num_words, int full);
size_t read_16bitpcm_file(const std::string & filename, unsigned char **pcm);


int main(int argc, char **argv) {
  // open the library
  char nameLib[] = "libpykaldi.so";
  void *lib = dlopen(nameLib, RTLD_NOW);
  if (!lib) {
      printf("Cannot open library: %s\n", dlerror());
      return 1;
  }   
  // load functions from shared library
  CKDW_constructor_t new_Decoder = load_function<CKDW_constructor_t>("new_KaldiDecoderWrapper", lib);
  if (!new_Decoder) return 2;
  CKDW_void_t del_Decoder = load_function<CKDW_void_t>("del_KaldiDecoderWrapper", lib);
  if (!del_Decoder) return 3;
  CKDW_setup_t setup = load_function<CKDW_setup_t>("Setup", lib);
  if (!setup) return 4;
  CKDW_void_t reset = load_function<CKDW_void_t>("Reset", lib);
  if (!reset) return 5;
  CKDW_frame_in_t frame_in = load_function<CKDW_frame_in_t>("FrameIn", lib);
  if (!frame_in) return 6;
  CKDW_decode_t decode = load_function<CKDW_decode_t>("Decode", lib);
  if (!decode) return 7;
  CKDW_void_t finish_input = load_function<CKDW_void_t>("FinishInput", lib);
  if (!finish_input) return 8;
  CKDW_prep_hyp_t prep_hyp = load_function<CKDW_prep_hyp_t>("PrepareHypothesis", lib);
  if (!prep_hyp) return 9;
  CKDW_get_hyp_t get_hyp = load_function<CKDW_get_hyp_t>("GetHypothesis", lib);
  if (!get_hyp) return 10;

  // use the loaded functions
  CKaldiDecoderWrapper *d = new_Decoder();
  int retval = setup(d, argc, argv);
  if(retval != 0)
    return retval;

  // read the saved pcm with headers like data
  unsigned char * pcm;
  std::string filename("pykaldi/decoders/test.wav");
  KALDI_WARN << "DEBUG";
  size_t pcm_size = read_16bitpcm_file(filename, &pcm);
  KALDI_WARN << "DEBUG";
  
  // send data in at once, use the buffering capabilities
  size_t frame_len = 2120, pcm_position = 0;
  unsigned char *frame = new unsigned char[frame_len];
  while(pcm_position + frame_len < pcm_size) {
    pcm_position = next_frame(frame, frame_len, pcm, pcm_position);
    frame_in(d, frame, frame_len);
  }
  delete[] frame;

  // tell the decoder that features input ended
  finish_input(d);

  KALDI_WARN << "DEBUG";

  // decode() returns false if there are no more features for decoder
  while(decode(d)) {
      int full; 
      size_t num_words = prep_hyp(d, &full);
      int * word_ids = new int[num_words];
      get_hyp(d, word_ids, num_words);
      printHyp(word_ids, num_words, full);
      delete[] word_ids;
  } 
  // Obtain last hypothesis
  {
      int full; 
      size_t num_words = prep_hyp(d, &full);
      int * word_ids = new int[num_words];
      get_hyp(d, word_ids, num_words);
      printHyp(word_ids, num_words, full);
      delete[] word_ids;
  }
  // KALDI_WARN << "DEBUG";
  del_Decoder(d);
  // KALDI_WARN << "DEBUG";

  dlclose(lib);
  return 0;
}

void printHyp(int *word_ids, size_t num_words, int full) {
  if(full) 
    std::cout << "full hypothesis";
  else 
    std::cout << "partial hypothesis";
  std::cout << ", decoded words: " << num_words << std::endl;
  // print the words
  for(size_t j = 0; j < num_words; ++j)
    std::cout << word_ids[j] << " ";
  std::cout << std::endl;
}


template<class FT> FT load_function(const char *nameFce, void *lib) {
  FT f = NULL;

  dlerror();  // reset errors
  if (!lib) {
      printf("Cannot open library: %s\n", dlerror());
      return NULL;
  }   

  dlerror();  // reset errors
  f = (FT)dlsym(lib, nameFce); 
  const char *dlsym_error = dlerror();
  if (dlsym_error) {
      printf("Cannot load symbol '%s', %s\n", nameFce, dlsym_error );
      dlclose(lib);
      return NULL;
  }

  return f;
}

void fill_frame_random(unsigned char *frame, size_t size) {
  for(size_t i=0; i<size; ++i) {
    frame[i] = random() & 0xff;
  }
}

size_t read_16bitpcm_file(const std::string & filename, unsigned char **pcm) {
  size_t size = 0;
  *pcm = NULL;

  std::ifstream file(filename.c_str(), std::ios::in|std::ios::binary|std::ios::ate);
  if (file.is_open()) {
    size = file.tellg();
    *pcm = new unsigned char [size];
    file.seekg(0, std::ios::beg);
    file.read((char *)*pcm, size);
    file.close();
  }
  return size;
}

size_t next_frame(unsigned char * frame, size_t frame_len,
                  unsigned char *pcm, size_t pcm_position) {
  for(size_t i=0; i < frame_len; ++i) {
    frame[i] = pcm[pcm_position + i];
  }
  return pcm_position + frame_len;
}
