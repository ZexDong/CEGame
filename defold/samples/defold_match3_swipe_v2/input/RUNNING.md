# Startup and delivery

This package can be copied independently. Use Defold Open starter_project/game.project and Build, or execute in starter_project/ : 

```bash
DEFOLD_JAR="${DEFOLD_BOB_JAR:?Set DEFOLD_BOB_JAR to the installed Bob JAR}"
: "${DEFOLD_JAVA:?Set DEFOLD_JAVA to the installed Java executable}"
"$DEFOLD_JAVA" -Dcom.google.protobuf.use_unsafe_pre22_gencode=true -cp "$DEFOLD_JAR" com.dynamo.bob.Bob --root . --platform arm64-macos --variant debug --archive build bundle
```

This project has no remote dependencies. Use the following read-only command to list the actual executable files, Run the only game executable file listed, Do not guess the file name: 

```bash
find build/default -type f -path '*/Contents/native desktop/*' -perm -u+x -print
```

from starter_project/ Start as the working directory. stdout/ Console and log.txt Contains logs; dashboard.jsonl Generated in the working directory, Each time a new process starts, the file will be truncated. Save first when retaining historical evidence; Do not share the same output directory with another game. Close with the window close button; If using the command line, Just terminate this startup and record Recorded PID, Not used killall/pkill. 

Empty projects only display the default background, Log output CAMPAIGN_STARTER_READY, The snapshot is not_ready; Available Q Exit. This is not the completed version of the interface. The completed version must be replaced with the real state of the space and interface, Fixed successful snapshots cannot be used instead of gameplay. Graphic session / Permission errors and compilation failures are handled separately. Only verify the local machine native host native desktop route, do not promise other platforms have been tested. 

complete the implementation and keep the source files, resources and permissions; do not copy the build cache, history log or private evaluation into the submission. Public campaign.json and naming-tables.json has been packaged with the project's benchmark/ directory, Available Defold Built-in sys.load_resource After reading json.decode; This is just static demand data, Not a state control interface.
