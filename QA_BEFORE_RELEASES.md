# Release QA

1. Confirm a clean topic branch and review every changed/deleted path.
2. Run `make clean && make -j8 && make test -j8` with no compiler warnings.
3. Run `make test-qwen4-kernels test-qwen4-q2 test-qwen4-prefill-reuse`.
4. Run `python3 tests/test_model_download.py`.
5. With Q2 or Q4 available, run MTP depth, checkpoint/rewind, steering, eval,
   benchmark, and server smoke tests listed in `AGENTS.md`.
6. With the projector and checkpoint available, run the Qwen vision parity test.
7. Run StarForge's parity oracle: tokens identical, speed delta within 2%.
8. Check `./sf-q3-8flash --help`, server port 8004, default model symlink, home,
   lock, and simultaneous startup with upstream.
9. Confirm docs mention only this child and `LICENSE` is unchanged.
10. Commit, push, and tag only after explicit authorization.
