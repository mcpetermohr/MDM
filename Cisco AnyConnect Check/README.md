# Cisco AnyConnect release history

Run on macOS or Linux with Bash, curl, and Perl:

```bash
bash check-anyconnect.sh
```

No browser, Node.js, Cisco login, or Python is needed. The script reads Cisco's
public Secure Client 5.1 release notes. It records only headings for the main
Secure Client releases, excluding separate module versions such as Secure
Firewall Posture and Zero Trust Access.

`data/anyconnect-history.csv` stores version, the date published in that release's
section (blank if absent), first observation date in UTC, and the source URL.
The initial run imports all documented releases; later runs preserve prior
entries even if Cisco removes them. Dates can be updated if Cisco corrects them.
`first_seen` is the observation date, not the historical release date.

`data/anyconnect-latest.json` contains exactly `version` and `release_date` for the
latest documented release. Dates use YYYY-MM-DD; if Cisco omits a date, it is
JSON `null`. Override its location with `LATEST_FILE`. By default it is saved
next to `HISTORY_FILE`. Failed fetches or parsing leave both files untouched.

Output status is `baseline`, `unchanged`, or `new_version`. Successful checks exit
0, including new releases. Fetch/parse failures exit nonzero and preserve history.
The script refuses an apparent downgrade and checks that the newest release
heading agrees with the document title. Run one check at a time for a given
history file.

The coverage is the 5.1 branch, not every Cisco client branch or platform. Release
notes publication does not guarantee a package is already available to download.
Review the source if Cisco introduces a new release branch or changes page markup.

## GitHub

Copy `check-anyconnect.sh`, `data/`, and `.github/` to the root of your GitHub
repository and commit them to its default branch. The included workflow runs
daily at 09:15 Europe/Copenhagen and supports a manual run in the Actions tab.
It commits changes to the CSV, keeping history across fresh GitHub runners, and
writes the detected version and status to the Actions run summary.

## Notifications

GitHub run summaries do not send an alert by themselves. To get workflow email,
open your GitHub Settings > Notifications, enable Email for Actions, and leave
"Only notify for failed workflows" unchecked. This sends run-status emails,
including successful daily checks; it is not limited to newly found releases.
Scheduled-run notifications normally go to the workflow creator (or the person
who last changed its cron schedule).

For alerts only on a new software version, add a step conditioned on
`steps.releases.outputs.status == 'new_version'` that creates a GitHub issue, then
watch Issues for the repository and enable email notifications. Alternatively,
send to an explicitly configured email or chat destination. This setup does not
yet create issues or send messages. Failure-only Actions notifications can be
enabled separately to catch failed checks.

GitHub notification documentation:
https://docs.github.com/en/subscriptions-and-notifications/how-tos/managing-github-actions-notifications

The workflow needs repository write permissions. Branch rules that prohibit bot
pushes will cause the save step to fail; use a repository where those writes are
allowed or adapt the persistence step to your repository policy. No workflow has
been uploaded or enabled by this local setup.

## Optional local settings

```bash
# Separate history for testing
HISTORY_FILE=/tmp/anyconnect-history.csv bash check-anyconnect.sh

# Test parsing using a saved HTML response without a network request
NOTES_FILE=/path/to/release-notes.html HISTORY_FILE=/tmp/test-history.csv bash check-anyconnect.sh
```
