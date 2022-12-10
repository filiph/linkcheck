FROM dart

RUN dart pub global activate linkcheck

ENTRYPOINT ["/root/.pub-cache/bin/linkcheck"]
