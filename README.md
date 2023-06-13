SimulationCraft Addon
=====================

This addon collects information about your character and presents a text version suitable for running in Simc

Usage
=====

Type `/simc` in-game to display text input that you can copy/paste to SimulationCraft.

`/simc nobags` will only output character on your gear, not items in your bags.

`/simc minimap` will toggle the minimap icon.

`/simc [Item Link]` can be used to add additional items to the output. For example, type `/simc`, add a space, then
shift left-click an item (from chat, a recent boss drop, or an item from a vendor) and that item will be added as a
comment below bag items in the text. WoW chat does have a character limit so the output may only contain the first 2-3
items that you link.

FAQ
===

### Why are some item names missing from the comments?

First, this warning does not impact the sim in any way - it only makes it a bit harder to know which
line is for which item for people reading the input.

Some addons that do big database updates can unintentionally cause problems for others. Usually it's
completionist or transmog addons (All The Things, Can I Mog It, etc) that need to do a bunch of work
on login and that can sometimes prevent the SimulationCraft addon from being able to show item names.

If you run /simc again a bit later once the database updates are done, it should resolve the issue and show
the item names in comments. You may need to run /simc a couple of times for the info to be available.


Maintainers
-----------

* navv
* seriallos
* aethys
* Theck (retired)
