module alt.blockheap;

/**
Modified code from Tango.
Author:  Michael Rynn
*/

import std.stdint;

private
{
	import core.memory;
	import std.c.string;
}
 /** heap of chunks of same sized blocks, the only feature being their size
	 Adjusted for non-gc usage, 
 */
version(NoGarbageCollection)
{
	private enum DoDeletes = true;
}
else {
	private enum DoDeletes = false;
}

/// for no garbage collection, 
class BlockHeap
{
    struct element
    {
        element *next;
    }

    struct chunkHeader
    {
        /**
         * The next chunk in the chain
         */
        chunkHeader *next;
        /**
         * The previous chunk in the chain.  Required for O(1) removal
         * from the chain.
         */
        chunkHeader *prev;

        /**
         * The linked list of free elements in the chunk.  This list is
         * amended each time an element in this chunk is freed.
         */
        element *freeList;

        /**
         * The number of free elements in the freeList.  Used to determine
         * whether this chunk can be given back to the GC
         */
        uintptr_t numFree;

        /**
         * Allocate a T* from the free list.
         */
        void *allocateFromFree()
        {
            element *x = freeList;
            freeList = x.next;
            //
            // clear the pointer, this clears the element as if it was
            // newly allocated
            //
            x.next = null;
            numFree--;
            return cast(void*)x;
        }

        // return number of free nodes
        uintptr_t deallocate(void *t, uintptr_t nsize)
        {
            //
            // clear the element so the GC does not interpret the element
            // as pointing to anything else.
            //
            memset(t, 0, nsize);
            element *x = cast(element *)t;
            x.next = freeList;
            freeList = x;
            return (++numFree);
        }

    }
    size_t chunkSize_;
    size_t nodeSize_;  // must be greater or equal to void*

	uintptr_t nodeSize() { return nodeSize_; } @property
    /**
     * The chain of used chunks.  Used chunks have had all their elements
     * allocated at least once.
     */
    chunkHeader *used = null;

    /**
     * The fresh chunk.  This is only used if no elements are available in
     * the used chain.
     */
    chunkHeader *fresh = null;

    /**
     * The next element in the fresh chunk.  Because we don't worry about
     * the free list in the fresh chunk, we need to keep track of the next
     * fresh element to use.
     */
    uintptr_t nextFresh = 0;

	// gc_addrof is not working.  Need a list of full blocks, as well as blocks with a free space.
	version(NoGarbageCollection)
	{
		chunkHeader* fullList;

		chunkHeader* findHeader(void *t)
		{
			auto mlimit = chunkHeader.sizeof + nodeSize_ * chunkSize_;
			if (fresh !is null)
			{
				if ( (cast(ubyte*)fresh + chunkHeader.sizeof) <= t && (cast(void*)fresh+mlimit) > t)
				{
					return fresh;
				}
			}			
			if (used !is null)
			{
				auto start = used;
				auto test = start;
				for(;;)
				{
					if ( (cast(ubyte*)test + chunkHeader.sizeof) <= t && (cast(void*)test+mlimit) > t)
					{
						return test;
					}				
					test = test.next;
					if (test == start)
						break;
				}
			}
			return null;
		}

	}

    this(BlockHeap hp)
    {
        if (hp !is null)
        {
            nodeSize_ = hp.nodeSize_;
            chunkSize_ = hp.chunkSize_;
        }
    }

	this(uintptr_t nsize, uintptr_t chunk = 0)
	{
		nodeSize_ = nsize;
		chunkSize_ = (chunk == 0) ? (4095 - ((void *).sizeof * 3) - uintptr_t.sizeof) / nsize : chunk;
	}

	~this()
	{
		explode(DoDeletes);
	}
	/// Unlink chain for garbage collection, or destroy completely
    void explode(bool del)
    {
        chunkHeader*  val;
        val = used;
        while (val !is null)
        {
            chunkHeader* nextUsed = val.next;
			if (del)
				GC.free( val );
			else {
				val.next = null;
				val.prev = null;
			}
            val = nextUsed;
            if (used == val)
                break;
        }
        if (fresh !is null && del)
            GC.free( fresh );

        used = null;
        fresh = null;
    }
    /**
     * Allocate a T*
     */
    void* allocate()
    {
        if(used !is null && used.numFree > 0)
        {
            //
            // allocate one element of the used list
            //
            void* result = used.allocateFromFree();
            if(used.numFree == 0)
                //
                // move used to the end of the list
                //
                used = used.next;
            return result;
        }

        //
        // no used elements are available, allocate out of the fresh
        // elements
        //
        if(fresh is null)
        {
            fresh = cast(chunkHeader*) GC.calloc( chunkHeader.sizeof + nodeSize_ * chunkSize_);
            nextFresh = 0;
        }

        void*  result = cast(void*) (fresh + 1) + nodeSize_ * nextFresh;
        if(++nextFresh == chunkSize_)
        {
            if(used is null)
            {
                used = fresh;
                fresh.next = fresh;
                fresh.prev = fresh;
            }
            else
            {
                //
                // insert fresh into the used chain
                //
                fresh.prev = used.prev;
                fresh.next = used;
                fresh.prev.next = fresh;
                fresh.next.prev = fresh;
                if(fresh.numFree != 0)
                {
                    //
                    // can recycle elements from fresh
                    //
                    used = fresh;
                }
            }
            fresh = null;
        }
        return result;
    }
    /+
    void*[] allocate(uint count)
    {
        return new void*[count];
    }
    +/
    // add at least nNodes to the used list
    void preAllocate(uintptr_t nNodes)
    {
        // allocate chunks and setup used linked lists, add to used
        auto alloc_chunks = (nNodes + chunkSize_-1)/ chunkSize_;

        for(uintptr_t i = 0; i < alloc_chunks; i++)
        {
            auto hdr = cast(chunkHeader*) GC.calloc( chunkHeader.sizeof + nodeSize_ * chunkSize_);
            void* p = cast(void*)(hdr+1);
            for(uint k = 0; k < chunkSize_; k++, p += nodeSize_)
            {
                element *x = cast(element *)p;
                x.next = hdr.freeList;
                hdr.freeList = x;
            }
            hdr.numFree = chunkSize_;
            if(used is null)
            {
                used = hdr;
                hdr.next = hdr;
                hdr.prev = hdr;
            }
            else
            {
                hdr.prev = used.prev;
                hdr.next = used;
                hdr.prev.next = hdr;
                hdr.next.prev = hdr;
                used = hdr;
            }
        }
    }
    /**
     * free a T*
     */
    void collect(void* t)
    {
        //
        // need to figure out which chunk t is in
        //
		version(NoGarbageCollection)
		{
			chunkHeader *cur = findHeader(t);
		}
		else {
			chunkHeader *cur = cast(chunkHeader *)GC.addrOf(t);
		}

        if(cur !is fresh && cur.numFree == 0)
        {
            //
            // move cur to the front of the used list, it has free nodes
            // to be used.
            //
            if(cur !is used)
            {
                if(used.numFree != 0)
                {
                    //
                    // first, unlink cur from its current location
                    //
                    cur.prev.next = cur.next;
                    cur.next.prev = cur.prev;

                    //
                    // now, insert cur before used.
                    //
                    cur.prev = used.prev;
                    cur.next = used;
                    used.prev = cur;
                    cur.prev.next = cur;
                }
                used = cur;
            }
        }

        if(cur.deallocate(t, nodeSize_) == chunkSize_)
        {
            //
            // cur no longer has any elements in use, it can be deleted.
            //
            if(cur.next is cur)
            {
                //
                // only one element, don't free it.
                //
            }
            else
            {
                //
                // remove cur from list
                //
                if(used is cur)
                {
                    //
                    // update used pointer
                    //
                    used = used.next;
                }
                cur.next.prev = cur.prev;
                cur.prev.next = cur.next;
                delete cur;
            }
        }
    }

    void collect(void*[] t)
    {
        if(t !is null)
            delete t;
    }
	/+
    /**
     * Deallocate all chunks used by this allocator.  Depends on the GC to do
     * the actual collection
     */
    bool collect(bool all = true)
    {
        used = null;

        //
        // keep fresh around
        //
        if(fresh !is null)
        {
            nextFresh = 0;
            fresh.freeList = null;
        }

        return true;
    }
	+/
}
