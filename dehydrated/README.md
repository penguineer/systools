# Dehydrated wrapper and check script

Wrap dehydrated calls so that cron e-mails are only sent when the call fails or new certificates are issued. Also check if available certificates are not about to expire too soon.

## Usage

Currently dehydrated is assumed at `/usr/local/bin/dehydrated` with it's configuration in `/usr/local/etc/dehydrated`. If you have a different setup, you need to adapt the scripts accordingly.

### dehy-wrap.sh

Configuration (so far) is in the script itself if necessary.

When an integer command-line argument is provided, the script will output its result if it has more lines than this number states.

### dehy-check.sh

Check if there are any LetsEncrypt certificated that will expire within the next 10 days.
This is an indication for a malfunctioning dehydrated setup.

### with cron

I use the following cron entries (for root):
```
0 3 * * * /usr/local/bin/dehy-wrap.sh 6
0 4 * * * /usr/local/bin/dehy-check.sh
```

## Next steps

* The line count is implemented to get an e-mail when deyhdrated issues new certificates. Obviously this should be done (at least) via a grep for signal strings or via a special return code in dehydrated.
* Configuration should be kept outside the scripts.
