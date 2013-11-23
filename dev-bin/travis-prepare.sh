#!/bin/sh
yes | perl -MCPAN::FirstTime -e 'CPAN::FirstTime::init'
cpanm --verbose Module::Install Module::Install::CPANfile
