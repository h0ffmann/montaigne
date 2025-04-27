# Montaigne Project TODOs

## License Management

- [ ] Add explicit license acceptance prompt in code for TTS model download
- [ ] Document license requirements in CONTRIBUTING.md
- [ ] Research commercial licensing options for XTTSv2 if needed
- [ ] Add license check in CI/CD pipeline

## Features

- [ ] Implement proper tone handling in TTS synthesis
- [ ] Add more comprehensive error handling for license-related issues
- [ ] Create automated tests for license acceptance flow
- [ ] Add YouTube integration to automatically:
  - [ ] Download audio from YouTube video ID
  - [ ] Extract clean voice track using voice separation
  - [ ] Use as speaker reference for TTS

## Documentation

- [x] Add license section to README explaining requirements (Initial version added)
- [ ] Document how to handle license changes/updates
- [ ] Add FAQ about commercial use cases

To check license status:
```bash
# Check TTS license acceptance
just run -- --check-license
```
