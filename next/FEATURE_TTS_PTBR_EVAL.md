# Brazilian Portuguese TTS Resources & Evaluation Tools

## Best TTS Models for Brazilian Portuguese

1. **XTTS Model**
   - Supports Brazilian Portuguese among other languages
   - Available through the Coqui-ai/TTS framework
   - One of the most popular options for multilingual TTS
   - Though Coqui shut down in 2024, the code remains available on GitHub

2. **VITS**
   - End-to-end model that performs well for Brazilian Portuguese when fine-tuned
   - Advanced neural network-based approach with good quality results
   - Can be fine-tuned on Portuguese datasets

3. **GlowTTS and GradTTS with HiFi-GAN**
   - Acoustic models paired with the HiFi-GAN vocoder
   - GradTTS+HiFi-GAN achieved naturalness scores close to commercial models
   - Strong performance in tests for Brazilian Portuguese

4. **TTS-Portuguese Corpus Models**
   - Based on an open-source corpus specifically created for speech synthesis in Brazilian Portuguese
   - Includes synthesized samples using Griffin-Lim and WaveRNN vocoders
   - Available on GitHub by Edresson Casanova
   - Demonstrated good performance with Tacotron 2 model achieving 4.03 MOS value

5. **MeloTTS**
   - One of the most downloaded TTS models on Hugging Face
   - Offers multilingual support which may include or be adaptable to Brazilian Portuguese
   - Real-time inference capabilities optimized for fast performance

6. **Spark-TTS**
   - Leverages large language models (specifically Qwen2.5) for speech synthesis
   - Features zero-shot voice cloning capabilities
   - While not specifically mentioned for Portuguese, its multilingual capabilities may make it suitable

## Other Resources

- **THLS Dataset**
  - Open-source dataset for Brazilian Portuguese speech processing
  - Contains 1000 phonetically balanced sentences
  - Useful for training custom TTS models

- **MARY Framework**
  - Work has been done on developing a complete TTS system for Brazilian Portuguese
  - Based on hidden Markov model (HMM) speech synthesis
  - Older approach compared to neural network-based methods

- **TaRSila Project**
  - Project aimed at growing speech datasets for Brazilian Portuguese
  - Includes resources for ASR, multi-speaker TTS, speaker identification, and voice cloning
  - Developed by the Center for Artificial Intelligence at the University of São Paulo

## Voice Similarity Evaluation Tools

1. **Resemblyzer**
   - Python package using deep learning to analyze and compare voices
   - Useful for speaker verification, fake speech detection, and voice similarity comparison
   - Can generate embeddings for comparing voice characteristics

2. **Cosine Similarity of Voice Embeddings**
   - Uses 256-dimensional Resemblyzer voice embeddings
   - Calculates cosine similarity between original speaker embedding and synthesized embedding
   - Helps determine which experiment delivers the most similar voice to the original

3. **CLVP Metric**
   - CLIP-like architecture measuring similarity of text and voice clips
   - Useful for evaluating Text-to-Voice models
   - Includes scripts for computing both CLVP score and Frechet distance

4. **Speaker Verification Models**
   - Tools for calculating equal error rate and thresholds for speaker verification
   - Useful for measuring voice similarity in fine-tuning

5. **SIM-o and SIM-r Metrics**
   - SIM-o measures similarity between generated and original target speeches
   - SIM-r measures similarity concerning target speech reconstructed from original speech

6. **MOS (Mean Opinion Score)**
   - Method for evaluating voice quality through human assessment
   - Standard in the field despite subjective nature
   - Often used for long-form content evaluation

7. **NannyML Data Drift Detection**
   - Detects subtle changes in audio that may not be obvious to human listeners
   - Reliable approach to evaluate TTS system performance

## STT Resources for Evaluation of Synthesis Quality

1. **Whisper ASR**
   - Open-source speech recognition system from OpenAI
   - Trained on 680,000 hours of multilingual data
   - Can transcribe speech in multiple languages including Portuguese
   - Excellent for evaluating TTS quality through transcription accuracy

2. **SpeechBrain**
   - "All-in-one" speech toolkit with strong multilingual support
   - Handles speech recognition, synthesis, and language models
   - Can be used to transcribe and evaluate synthesized speech
   - Has competitive recipes on more than 40 datasets supporting 20 speech processing tasks

3. **Word Error Rate (WER) and Character Error Rate (CER)**
   - Standard metrics to evaluate synthesis robustness
   - Measures transcription accuracy of synthesized speech
   - Can be calculated using ASR models like CTC-based HuBERT-Large or Whisper

4. **TaRSila ASR Models**
   - Specific ASR models for Brazilian Portuguese
   - Developed at the University of São Paulo
   - Can be used to evaluate TTS quality through transcription accuracy

5. **Speech Recognition Evaluation Toolkit**
   - Tools for measuring Word Error Rate and Word Information Loss
   - Calculates Levenshtein Distance at word level
   - Provides statistics on insertions, deletions, and mismatches
   - Includes color highlighting to visualize differences between original and generated text

6. **Automatic Evaluation Protocol**
   - Frameworks for systematic evaluation of zero-shot TTS models
   - Includes metrics for synthesis robustness and transcription accuracy
   - Can be adapted for Brazilian Portuguese evaluation

## Implementation Example Workflow

For a complete evaluation pipeline of a Brazilian Portuguese TTS system, consider this workflow:

1. **Train/Fine-tune TTS Model**
   - Use TTS-Portuguese Corpus or THLS Dataset
   - Select model architecture (VITS, GradTTS, Tacotron 2, etc.)
   - Train with appropriate hyperparameters

2. **Voice Similarity Evaluation**
   - Generate embeddings using Resemblyzer
   - Calculate cosine similarity between original and synthesized voices
   - Optionally run MOS tests with native speakers

3. **Transcription Quality Evaluation**
   - Use Whisper or other ASR model to transcribe synthesized speech
   - Calculate WER and CER compared to original text
   - Analyze error patterns (substitutions, insertions, deletions)

4. **Grammar and Spelling Analysis**
   - Use the transcribed text to evaluate linguistic accuracy
   - Check for grammatical errors or mispronunciations
   - Evaluate handling of Portuguese-specific linguistic features (accents, gender agreement, etc.)

5. **Iteration and Improvement**
   - Identify patterns in errors
   - Retrain or fine-tune model based on evaluation results
   - Re-evaluate using the same metrics for consistent comparison

## References and Links

- TTS-Portuguese Corpus: https://github.com/Edresson/TTS-Portuguese-Corpus
- Resemblyzer: https://github.com/resemble-ai/Resemblyzer
- TaRSila Project: https://sites.google.com/view/tarsila-c4ai
- Speech Recognition Evaluation: https://github.com/symblai/speech-recognition-evaluation
- Whisper ASR: https://github.com/openai/whisper
- XTTS: https://github.com/coqui-ai/TTS
- VITS: https://github.com/jaywalnut310/vits