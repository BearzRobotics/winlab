*Draft for owner review.* Technical skill gets a fault fixed; procedure keeps the fix from causing the next one. These habits are what separate an administrator from someone who knows commands.

## Documentation

Write down, while you work, not afterward:

- what the problem was, in the user's words and in yours
- what you checked, in order, and what each check showed
- what you changed, on which machine, at what time
- how you confirmed it was fixed, and how to undo the change

A **problem record** with those four parts is the same thing the troubleshooting method asks for. Keep inventory facts (hostnames, addresses, owners, warranty, install dates) in one place rather than in memory.

## Change management

Changing a production system is a controlled act:

1. **Request:** what is changing, why, who asked.
2. **Risk assessment:** what could break, who is affected, can it be undone?
3. **Approval** from whoever owns the system.
4. **Plan and back-out plan:** the steps, plus how to return to the previous state (a snapshot, a backup, the old setting written down).
5. **Window:** do it when the impact is smallest, and tell the affected people.
6. **Verify and record:** test the result, close the request.

This course's labs follow the same shape: a snapshot is the back-out plan, and the check is the verification.

## Backups and recovery

The **3-2-1 rule**: three copies, on two kinds of media, one off-site. A backup that has never been restored is a hope, not a backup. Know the difference between full, incremental and differential, and define two numbers with the business: how much data loss is acceptable (RPO) and how long recovery may take (RTO).

## Communication and professionalism

- Tell the user what you found and what happens next in plain words; avoid jargon.
- Do not blame, do not guess aloud, and do not promise a time you cannot keep.
- Treat what you see on a user's machine as confidential.
- Say when something is outside your authority and escalate with your problem record attached.

## Safety and the work environment

Use anti-static precautions with hardware, lift with your legs, power off and unplug before opening equipment, and follow your site's rules for disposal of batteries and electronics. Do not run unfamiliar scripts on a production machine.

## Scripts and automation as procedure

A script is a written, repeatable procedure. Keep scripts under version control, give them clear names, test them on a lab machine first, and log what they change.

## Check yourself

1. What are the two things a change request needs beyond "what we will do"?
2. Why is an untested backup a risk?
3. What belongs in a problem record that you will hand to another technician?
