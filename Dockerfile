FROM dart

RUN pub global activate linkcheck

ENTRYPOINT ["/root/.pub-cache/bin/linkcheck"]
