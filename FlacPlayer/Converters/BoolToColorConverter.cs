using System;
using System.Globalization;
using System.Windows;
using System.Windows.Data;
using System.Windows.Media;

namespace FlacPlayer.Converters
{
    public class BoolToColorConverter : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, CultureInfo language)
        {
            SolidColorBrush result;
            if ((bool)value)
            {
                result = new SolidColorBrush(Color.FromRgb(88, 57, 212));
                if (System.Convert.ToInt16(parameter) == 1)
                {
                    result = new SolidColorBrush(Color.FromRgb(244, 244, 245));
                }
            }
            else
            {
                result = new SolidColorBrush(Color.FromRgb(244, 244, 245));
                if (System.Convert.ToInt16(parameter) == 1)
                {
                    result = new SolidColorBrush(Color.FromRgb(88, 57, 212));
                }
            }

            return result;
        }

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo language)
        {
            throw new NotImplementedException();
        }
    }
}
