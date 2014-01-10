Automarkup2
===========

Automarkup 2, Electric Boogaloo! 

This project aims to take the raw XML output of Congressional bills from GPO and apply additional tags


In short, this script:

* Retrieves a set of XML documents

* Attempts to discover items within the document that warrant expanded tagging

* Writes the additional changes

* Posts the new documents to its source server

Specifically the tool is designed to enhance the work done at the Cato Institute's [Deepbills project](http://www.cato.org/resources/data) where a specific set of XML tags are added to Congressional bills in order to enhance their richness and allow more machine readability.

You can read about the [Cato Deepbills schema](http://namespaces.cato.org/catoxml/) in detail.

Nobody Cares
------------

The product is called Automarkup2 because there is an earlier corpus of code, entirely written in XQuery and dependent on running within BaseX, which uses a neural network concept of automatic tagging by finding existing tagged XML nodes and appling that tag to untagged segments in new bills. This works well in some circumstances when Congress re-uses entire blocks of text in new or modified bills and poorly when trivial edits are made. Automarkup2 is an effort to use a more expert system concept and apply automatic tags in a pre-identified and procedural method. 

Setting Up
----------

Automarkup2 is written in perl and depends on [Eric Mill](http://github.com/konklone)'s  [citation finder](https://github.com/unitedstates/citation), which it expects to find in its standalone CLI form, cite. The simplest way to install it is to use NPM and install 'citation'. Additional details can be found at the above link.

The perl code expects to find these modules

	* HTTP::Cookies
	* Time::localtime
	* Text::CSV
	* JSON
	* List::MoreUtils 'any'
	* File::Slurp
	* Cwd
	* DateTime
	* DateTime::Format::XSD
	* Data::Dumper

and all of them are available via [CPAN](http://search.cpan.org).

Getting the bills to mark up
----------------------------

As used by Cato, Automarkup2 connects to the Deepbills server to retrieve any bills currently in the system and lacking markup. You are free to do this yourself to try the results but Deepbills is a live operation and the aim is to markup as many bills as possible; in a perfect world running this script will download 0 documents.

In all likelyhood there will be some new bills at any given time, but you may wish instead to pre-populate the directory with some bills and set the skip_download flag to 1 in order to simply run on local documents. One way to accomplish this would be the same way the Deepbills project gets the bills initially: by using the [Congress Scraper](https://github.com/unitedstates/congress/) maintained by Sunlight and GovTrack to pull the bills from GPO's FDSys.

Running the markup
------------------

This tool will attempt to do markup on any file with the extension .xml in its directory. In theory it should simply do nothing if the citation finder returns no results but this theory has not been tested since it's not a concern in production; the download step removes any existing .xml files and will only download valid bills.

You may skip the markup step by enabling the skip_process flag but why would you want to? This function exists for internal use so that we can grab new documents and stop at that point, allowing us to later re-run over the same set for testing. This is accomplished by setting $skip_process = 1.

If you enable the debug flag by setting $debug = 1 the process will save some additional documents while processing as well as providing more verbose output. Yes yes, there should be a seperate verbose flag.

Yes yes, these should all be in a seperate config file. We know.

Posting the results
-------------------

Simply put, you cannot. This script includes functionality to connect to the Deepbills system and post the tagged output so that we can auto-tag new documents. This step requires authentication and you do not have it. The $skip_posting flag has been pre-set to 1 for you in order to save you the pain and disappointment of being denied.

Instead you will wish to look at the .new files in the directory after the processing has been done; they represent the original document with the new tags applied. If no tags were found that could be added then no document is created.

TODO
----

* Put flags and login details in a proper external config file
* Add functionality to seek markup items that match law popular names
* Add functionality to seek markup items that match known federal organizational unit, including Agencies and Bureaus
* Add functionality to seek markup items that match committees
* Cope with the fact that less-specific pre-tagged items from Congress with an external-xref surrounding them mean Mill's citation finder cannot find the entire cite
	Best current theory of how to do this is to round-trip remove and re-add the external-xref items before and after tagging, requiring maintaining a list of positions and then doing proper math on them as tags alter positions.

