#!/bin/env perl
#
#  Convert Westpac and other OFX file to QIF
#
package main;


#  Pragma
#
use strict qw(vars);
use vars qw($VERSION $Debug);


#  External modules
#
use IO::File;
use Finance::OFX::Parse;
use Finance::QIF;
use POSIX qw(strftime);
use Getopt::Long;
use Pod::Usage;
use FindBin qw($RealBin $Script);


#  Data::Dumper used in debugging only
#
use Data::Dumper;
$Data::Dumper::Indent=1;


#  Constants
#
use constant {


    #  Default date format for POSIX::strftime
    #
    QIF_DATE_FORMAT => '%d/%m/%Y',


    #  QIF Number field, options:
    #
    #  Financial Transaction ID: fitid (default)
    #  Check Number: checknum
    #  Either: fitid|checknum, checknum|fitid
    #  Combined: fitid<join>checknum, (e.g. fitid:checknum)
    #
    QIF_NUMBER_FIELD => 'fitid',


    #  QIF date field, options:
    #
    #  Date Posted: dtposted
    #  Date Actual: dtuser
    #
    QIF_DATE_FIELD => 'dtposted',


    #  QIF payee field, options:
    #
    #  None: none
    #  Payee: payee
    #  Name: name
    #  Either: name|payee, payee|name
    #  Combined: fitid<join>checknum, (e.g. fitid:checknum)
    #
    QIF_PAYEE_FIELD => 'payee',


    #  Output to stdout
    #
    OUTFILE => '-'

};


#  Version Info, must be all one line for MakeMaker, CPAN.
#
$VERSION='1.007';


#  Run main routine
#
exit ${&main(\@ARGV) || die 'unknown error'};


#===================================================================================================


sub getopt {


    #  Parse options and dispatch to actual work routine below
    #
    my $argv_ar=shift();


    #  Defaul options
    #
    my %opt=(

        qif_date_format  => +QIF_DATE_FORMAT,
        qif_date_field   => +QIF_DATE_FIELD,
        qif_number_field => +QIF_NUMBER_FIELD,
        qif_payee_field  => +QIF_PAYEE_FIELD,
        outfile          => +OUTFILE,
        infile           => [],

    );


    #  Get command line options
    #
    #Getopt::Long::Configure(qw(auto_help auto_version));
    GetOptions(
        \%opt,
        'help|?',
        'man',
        'version',
        'debug',
        'outfile=s',
        'infile=s@',
        'qif_date_format=s',
        'qif_number_field=s',
        'qif_date_field=s',
    ) || pod2usage(2);
    pod2usage(-verbose => 99, -sections => 'Synopsis|Options', -exitval => 1) if $opt{'help'};
    pod2usage(-verbose => 2) if $opt{'man'};
    $opt{'version'} && do {
        print "$Script version: $VERSION\n";
        exit 0
    };


    #  Get infile
    #
    unless (@{$opt{'infile'}}) {
        $opt{'infile'}=$argv_ar
    }
    unless (@{$opt{'infile'}}) {
        die "usage: $Script infile [ .. infile]";
    }


    #  Return option hash ref
    #
    debug('opt %s', Dumper(\%opt)) if ($Debug=$opt{'debug'});


    #  Done
    #
    return \%opt;

}


sub main {


    #  Get options
    #
    my $opt_hr=&getopt(shift());
    
    
    #  Declare vars
    #
    my @qif;
    my ($ofx_account_type, $ofx_qif_header, $ofx_lookup_trxn_ar, $ofx_lookup_id_ar, $qif_header, $ofx_account_id);


    #  Create lookup table based on OFX tree for Bank and credit card statement types.
    #
    my %qif_lookup=(

        creditcardmsgsrsv1 => [
            'Type:CCard',
            [qw(ccstmttrnrs ccstmtrs banktranlist stmttrn)],
            [qw(ccstmttrnrs ccstmtrs ccacctfrom acctid)]
        ],
        bankmsgsrsv1 => [
            'Type:Bank',
            [qw(stmttrnrs stmtrs banktranlist stmttrn)],
            [qw(stmttrnrs stmtrs bankacctfrom acctid)]
        ],

    );

    
    
    #  Iterate through infile(s)
    #
    foreach my $ofx_fn (map {glob($_)} @{$opt_hr->{'infile'}}) {

        #my ($ofx_fn, $qif_fn)=@{$opt_hr}{qw(infile outfile)};
        debug("ofx_fn: $ofx_fn");


        #  Slurp in OFX file
        #
        my $ofx_fh=IO::File->new($ofx_fn, O_RDONLY) ||
            die "unable to open file $ofx_fn, $!";
        my $ofx_data=do {local $/=undef; <$ofx_fh>};
        $ofx_data ||
            die "file $ofx_fn appears empty";


        #  Massage OFX file to insert CR's between header and body section, needed by
        #  Finance::OFX or it will choke
        #
        $ofx_data=~s/(.*?)<OFX>(.*)/$1\n<OFX>$2/;


        #  Fix empty memo fields which Finance::OFX does not seem to parse well
        #
        $ofx_data=~s/<MEMO>\s+/<MEMO><\/MEMO>\n/g;


        #  Create new OFX hash ref by parsing OFX file through Finance::OFX::Parse
        #
        my $ofx_hr=Finance::OFX::Parse::parse($ofx_data) ||
            die "unable to parse OFX data";
        debug('ofx_hr ^%s', Dumper($ofx_hr));


        #  Iterate through translating file
        #
        foreach my $key (keys %{$ofx_hr->{'ofx'}}) {
            if ($qif_header=$qif_lookup{$ofx_account_type=$key}[0]) {
                debug("ofx_qif_header:    $qif_header");
                ($ofx_qif_header, $ofx_lookup_trxn_ar, $ofx_lookup_id_ar)=
                    @{$qif_lookup{$ofx_account_type}}[0..2];
                last;
            }
        }
        $ofx_account_type ||
            die('unable to determine OFX account type');
        debug(
            join(
                "\n",
                (
                    'ofx_account_type:      %s',
                    'ofx_lookup_trxn_ar:    %s',
                    'ofx_lookup_id_ar:      %s',
                    )
            ),
            $ofx_account_type,
            Dumper($ofx_lookup_trxn_ar),
            Dumper($ofx_lookup_id_ar)
        );


        #  Descend into tree to get statement transactions as array
        #
        my $ofx_trxn_ar=$ofx_hr->{'ofx'}{$ofx_account_type};
        foreach my $key (@{$ofx_lookup_trxn_ar}) {
            $ofx_trxn_ar=$ofx_trxn_ar->{$key};
        }
        debug('ofx_trxn_ar: %s', Dumper($ofx_trxn_ar));



        #  Descend into tree to get account id information
        #
        $ofx_account_id=$ofx_hr->{'ofx'}{$ofx_account_type};
        foreach my $key (@{$ofx_lookup_id_ar}) {
            $ofx_account_id=$ofx_account_id->{$key};
        }
        debug("ofx_account_id: $ofx_account_id");


        #  Sanity check or quit
        #
        $ofx_trxn_ar ||
            die('unable to descend through ofx_hr tree to transactions');
        $ofx_account_id ||
            die('unable to descend through ofx_hr tree to account id');


        #  Now iterate through transactions
        #
        foreach my $ofx_trxn_hr (@{$ofx_trxn_ar}) {


            #  Hash lookup table. Overkill
            #
            my %qif_cr=(

                header => sub {
                    $ofx_qif_header
                },
                payee => sub {
                    &qif_field_format($ofx_trxn_hr, $opt_hr->{'qif_payee_field'}, qw(name payee));
                },
                number => sub {
                    &qif_field_format($ofx_trxn_hr, $opt_hr->{'qif_number_field'}, qw(checknum fitid));
                },
                date => sub {
                    strftime($opt_hr->{'qif_date_format'}, localtime($ofx_trxn_hr->{$opt_hr->{'qif_date_field'}}))
                },
                memo => sub {
                    $ofx_trxn_hr->{'memo'} if !ref($ofx_trxn_hr->{'memo'})
                },
                transaction => sub {
                    $ofx_trxn_hr->{'trnamt'}
                },
                _timestamp => sub {
                    $ofx_trxn_hr->{$opt_hr->{'qif_date_field'}}
                }

            );


            #  Now contruct final QIF transaction hash from lookup table
            #
            my %qif;
            foreach my $key (keys %qif_cr) {
                my $value;
                $qif{$key}=$value if ($value=$qif_cr{$key}->());
            }


            #  Store in array for later processing
            #
            debug('qif %s', Dumper(\%qif));
            push @qif, \%qif

        }
    }


    #  Now combing and print results in QIF format. Open output file
    #
    if (@qif) {

        my $qif_fn=$opt_hr->{'outfile'};
        my $out_fh=Finance::QIF->new(file => ">$qif_fn");
        debug("out_fh: $out_fh");


        #  Send out account header information
        #
        $out_fh->header('Account');
        $out_fh->write(
            {
                header => 'Account',
                name   => $ofx_account_id
            });


        #  Type:Bank or Type:CCard
        #
        $out_fh->header($ofx_qif_header);


        #  Sort output and send to QIF converter. Do not repeat trxns
        #
        my %fit_id;
        foreach my $qif_hr (sort {$a->{_timestamp} cmp $b->{_timestamp}} @qif) {
            next if $fit_id{$qif_hr->{'number'}}++;
            delete $qif_hr->{'_timestamp'};
            $out_fh->write($qif_hr);
        }


        #  Done
        #
        $out_fh->close();
    }
    else {
        die('no transactions processed');
    }

}


sub qif_field_format {

    my ($ofx_trxn_hr, $opt, @field)=@_;
    if ($opt eq 'none') {
        return undef;
    }
    elsif ($opt=~/^(\w+)\|(.*)/) {
        return $ofx_trxn_hr->{$1} || $ofx_trxn_hr->{$2};
    }
    elsif (grep {/$opt/} @field) {
        return $ofx_trxn_hr->{$opt}
    }
    elsif ($opt=~/^$field[0](.*)$field[1]$/) {
        return join($1, grep {$_} @{$ofx_trxn_hr}{@field});
    }
    elsif ($opt=~/^$field[1](.*)$field[0]$/) {
        return join($1, grep {$_} @{$ofx_trxn_hr}{@field[1, 0]});
    }
    else {
        die "unknowm option $opt";
    }

}


sub debug {

    printf STDERR (shift() . "\n", @_) if $Debug;

}

__END__

=head1 Name

ofx2qif.pl - parse and convert financial OFX files to Quicken QIF format

=head1 Synopsis

B<ofx2qif.pl> B<[OPTIONS]> B<INFILE> .. B[<INFILE>] > B<OUTFILE>

=head1 Options

=over 4

=item -h, --help

Show brief help message.

=back

=over 4

=item -m, --man

Show manual page

=back

=over 4

=item -v, --version

Show version information

=back

=over 4

=item --debug

Show debugging information

=back

=over 4

=item -o, --outfile

Output file, defaults to STDOUT

=back

=over 4

=item --qif_date_format

Date format for QIF files in POSIX strftime format. Defaults to '%d/%m/%Y' => 'dd/mm/yyyy'

=back

=over 4

=item --qif_date_field

Which OFX date field to use in QIF files - dtposted (default), dtuser

=back

=over 4

=item --qif_number_field

Which OFX number field to use in QIF files - fitid (default), checknum

=back

=over 4

=item --qif_payee_field

Which OFX payee field to use in QIF files - payee (default), name

=back

=head1 Description

The B<ofx2qif.pl> command will parse a financial insitution OFX response file (of type Bank or
Credit Card account) and convert to Quicken format.

=head1 Notes

Investment accounts are not handled yet. 

For each for the --qif_<name>_field options you can also use:

none:                   don't output this field at all

field1|field2:          use field1 if present in the transaction, or field2 if field1 not available

field1<join>field2:     combine field1 and field2 from the transactrion with character <join>

=head1 Examples

B<ofx2qif.pl> B<mybankdata.OFX>

=head1 Author

Written by Andrew Speer, andrew.speer@isolutions.com.au

=head1 Copying

Copyright (C) 2013 Andrew Speer. Free use of this software is granted under the terms of the GNU
General Public License (GPL)
