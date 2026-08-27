# PatronHelper
PatronHelper is a lightweight World of Warcraft addon designed to track the basic materials required to complete your current Patron/Client orders and automatically generates a click-to-search shopping list for you.

The shopping list is account-wide (shared across characters, including warbank counts). Bags, bank, reagent bank, and warbank are subtracted live when you view the list or search the Auction House, so importing several orders into one list does not double-count what you already own.

## Commands
Type `/ph` or `/patronhelper` in-game to toggle the shopping list interface.

- `/ph import` — import the currently open crafting order
- `/ph clear` — clear the shopping list (asks first)

## Usage
1. Open up your Profession crafting table and select a Crafting Order.
2. Open PatronHelper (`/ph`) or click the Patron Helper button on the Orders tab.
3. Click **Import Order**.
4. The addon will add reagents the customer did not provide. Import another order to combine missing materials into one list. The same order will not be imported twice.
5. Quantities on the list are what you still need after inventory. Green rows mean you already have enough.
6. *(Optional)* At the Auction House, click **Search in AH** to search for remaining items in Auctionator. (Requires [Auctionator](https://www.curseforge.com/wow/addons/auctionator)).
7. Shift-click a row to link the item. Right-click (or the **x**) to remove it. Click **Clear List** when you are done shopping.

Quality reagents are added as the lowest quality (usually Tier 1). Higher-quality versions you already own still count toward the total.
