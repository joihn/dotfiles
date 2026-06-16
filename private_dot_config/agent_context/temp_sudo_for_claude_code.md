## how to give claude code tmp access to sudo 

 global timestamp + sudo -v.
One-time setup — create a sudoers drop-in:
```
bashecho 'Defaults timestamp_type=global' | sudo tee /etc/sudoers.d/claude-global
echo 'Defaults timestamp_timeout=15'  | sudo tee -a /etc/sudoers.d/claude-global
sudo chmod 440 /etc/sudoers.d/claude-global
```

timestamp_type=global means once you authorize sudo in any terminal, you can use it without a second prompt in any other terminal for the timeout window. Igor's Writing
Then, mid-session when Claude hits a sudo wall, in any pane:

sudo -v          # type your password once; refreshes the global timestamp

Claude's sudo commands now work for ~15 min. When done, revoke immediately:
```
bashsudo -K          # kills the timestamp
```
This keeps the password as a barrier (you still type it), stores nothing, works without a GUI, and auto-expires. You can automate it with a wrapper or a PreToolUse hook — Igor Serebryany's claude-sudo wrapper enables global mode only for the session and revokes on exit, and someone in the issue thread converged on the same timestamp_type=global trick driven via a PreToolUse hook so Claude prompts you to authenticate on demand.
