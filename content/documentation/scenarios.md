---
title: Curiosity
---

# Test scenarios

One the main goal of Curiosity is to precisely describe its behavior in terms
of test scenarios. To do so, Curiosity supports running scripts: they are
textual sequences of commands that mimic closely what can be done through the
web interface.

As part of Curiosity's test suite, a collection of scenarios are run and their
results are compared to known sources of truth, called "golden files". This
makes sure that, as scenarios are created, and as Curiosity evolves, the system
continues to work as expected, and few bugs can be introduced inadvertantly.

# Example data

Entering enough data into the system to allow to execute (possibly manually,
through the web interface) a specific test scenario can be tedious if the
system is initially empty. Fortunately, scripts can also be used to generate
the necessary data and set the system state as desired.

A specific set of example data is available with Curiosity, called `state-0`.
(We envision that additional set of data could be created in the future.)

Note: if you are operating Curiosity yourself, you can initialize Curiosity's
state by running `cty run scenarios/state-0.txt`. Here is [an example
scenario](https://github.com/hypered/curiosity/blob/main/scenarios/0.txt), and
its [corresponding golden
file](https://github.com/hypered/curiosity/blob/main/scenarios/0.golden).

# `state-0`

We intend `state-0` to serve as common knowledge among the team working with
Curiosity. Here, we detail what it is comprised of.

Note: sometimes, we provide links to specific pages of the web application.
When those pages are displaying the live application state, it is possible that
the underlying data have changed and are no longer how they were when the
system was initialized.

## Users

- [Alice](/alice)
- [Mila](/mila)

## Legal entities

- [One S.A.](/entity/one)

## Business units

- [Alpha](/alpha)

## Forms

Forms data are held separately from the rest of the regular objects in what we
call the _staging area_. This is a place in memory where form data can be
edited and eventually submitted. When they are submitted, they are validated
against various rules. Only if they pass such validation, data are recorded in
the regular state.

In the staging area, invalid data can reside. The user can amend the data as
much as they desire. Interestingly, this allows us to have example data in the
staging area that will fail validation, and this can be used to exemplify
validation rules.

### Simple contract

- [Amount `-100`](/forms/edit/simple-contract/confirm-simple-contract/TBPJLIUG)
- [Amount `0`](/forms/edit/simple-contract/confirm-simple-contract/HNONWPTG)
- [Amount `100`](/forms/edit/simple-contract/confirm-simple-contract/RZEMQMNF)

Note: the validation rules are visible in the [source
code](/haddock/src/Curiosity.Data.SimpleContract.html#validateCreateSimpleContract).
We should try to expose them more clearly, both in the documentation, and in
the code.
