# hostmon
Learning project (unfinished) aiming to automatically deploy Icinga Monitoring master/control server and prepare and add other servers to monitoring.

## Background:
After I've learned about monitoring I attempted creating a set of scripts to fully automate processes of deploying the main monitoring server and adding existing machines as clients. I've made mistakes in the beginning that decided on the project not being completed despite many hours spent on it.

## Biggest mistakes and what I've learned from them:
#### 1. Asking for too little help in the planning phase:
I knew bash and decided to use it for everything. I wrote my own script to create, manage and maintain a file with all machines in the project (IP addresses, hostnames..) with sanity checks and limited self repair ability,  for which I invented my own config style.\
**Lesson learned:** Include others, also early in the development phase,  not only later when needing help with implementation. If I bounced my ideas from anyone they would tell me to use Terraform and eventually JSON/jq for the infra file. I ended up reinventing the wheel and burning many hours.

#### 2. Using the wrong tool for the job:
If you have a hammer, everything looks like a nail. I've used bash for everything - bash and provider's cli tools for provisioning instead of terraform. Bash scripts instead of Ansible for configuration management part of provisioning. I got really good at automating things with Bash, but didn't get much work done.\
**Lesson learned:** Tell experienced people how you're planning to do things and ask for feedback. Using right tools also helps keeping the work modular - having big parts of the project not coupled together and talking using an API, so they can be swapped and replaced with ease.

#### 3. Working from the bottom up instead top down:
Getting right into coding, working towards an unspecified bigger goal leads to much unplanned work being done on things that are not essential.\
**Lesson learned:** Start with the end in mind. Big abstractions, mock functions, pseudo code and only write code at the end. It feels like not getting anything done, but it's super effective because it ensures that work is always done towards the goal and you don't waste time wondering what to do next. 
