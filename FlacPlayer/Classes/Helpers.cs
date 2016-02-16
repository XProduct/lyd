using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace FlacPlayer
{
    class Helpers
    {
    }

    public static class Extensions
    {
        public static List<T> Shuffle<T>(this IList<T> passedList)
        {
            Random random = new Random();
            List<T> list = passedList.ToList();

            int n = list.Count;
            while (n > 1)
            {
                n--;
                int k = random.Next(n + 1);
                T value = list[k];
                list[k] = list[n];
                list[n] = value;
            }

            return list;
        }
    } 
}
