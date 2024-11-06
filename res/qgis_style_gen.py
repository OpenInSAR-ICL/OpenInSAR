import xml.etree.ElementTree as ET
import uuid
import colorsys
from copy import deepcopy

example_symbol_str = """
      <symbol name="0" is_animated="0" alpha="1" clip_to_extent="1" type="marker" frame_rate="10" force_rhr="0">
        <data_defined_properties>
          <Option type="Map">
            <Option name="name" type="QString" value=""/>
            <Option name="properties"/>
            <Option name="type" type="QString" value="collection"/>
          </Option>
        </data_defined_properties>
        <layer pass="0" enabled="1" id="{b791b201-c228-4942-a919-025a5bd90c60}" class="SimpleMarker" locked="0">
          <Option type="Map">
            <Option name="angle" type="QString" value="0"/>
            <Option name="cap_style" type="QString" value="square"/>
            <Option name="color" type="QString" value="122,4,3,255"/>
            <Option name="horizontal_anchor_point" type="QString" value="1"/>
            <Option name="joinstyle" type="QString" value="bevel"/>
            <Option name="name" type="QString" value="circle"/>
            <Option name="offset" type="QString" value="0,0"/>
            <Option name="offset_map_unit_scale" type="QString" value="3x:0,0,0,0,0,0"/>
            <Option name="offset_unit" type="QString" value="RenderMetersInMapUnits"/>
            <Option name="outline_color" type="QString" value="35,35,35,255"/>
            <Option name="outline_style" type="QString" value="no"/>
            <Option name="outline_width" type="QString" value="0"/>
            <Option name="outline_width_map_unit_scale" type="QString" value="3x:0,0,0,0,0,0"/>
            <Option name="outline_width_unit" type="QString" value="RenderMetersInMapUnits"/>
            <Option name="scale_method" type="QString" value="diameter"/>
            <Option name="size" type="QString" value="12"/>
            <Option name="size_map_unit_scale" type="QString" value="3x:0,0,0,0,0,0"/>
            <Option name="size_unit" type="QString" value="RenderMetersInMapUnits"/>
            <Option name="vertical_anchor_point" type="QString" value="1"/>
          </Option>
          <data_defined_properties>
            <Option type="Map">
              <Option name="name" type="QString" value=""/>
              <Option name="properties"/>
              <Option name="type" type="QString" value="collection"/>
            </Option>
          </data_defined_properties>
        </layer>
      </symbol>
"""

example_symbol = ET.fromstring(example_symbol_str)

def generate_color_values(index, number_of_elements):
    # Generate a color based on the index and the number of elements
    # The color should be a gradient from red to blue, through green
    # We can use hsv to generate the colors
    h = 240 * index / number_of_elements
    # saturation should drop to 30% in the middle
    middle = number_of_elements // 2
    s = 30 + 70 * abs(index - middle) / middle
    v = 100
    a = 255
    r, g, b = colorsys.hsv_to_rgb(h / 360, s / 100, v / 100)
    
    return r, g ,b, a

def generate_color(index, number_of_elements):
    r, g, b, a = generate_color_values(index, number_of_elements)
    return f'{int(r*255)},{int(g*255)},{int(b*255)},{a}'

def generate_symbol(index, number_of_elements):
    symbol = deepcopy(example_symbol)
    symbol.set('name', str(index))
    color = generate_color(index, number_of_elements)
    layer = symbol.find('layer')
    options = layer.find('Option')
    # find the color option
    color_option = options.find('Option[@name="color"]')
    color_option.set('value', color)
    return symbol

def generate_uuid():
    # Form: 881b03d5-21e5-4219-95d9-c98737917ff4
    uuid_str = str(uuid.uuid4())
    uuid_str_in_brackets = '{' + uuid_str + '}'
    return uuid_str_in_brackets

def generate_range_element(example, index, min_val, max_val):
    #   <range render="true" uuid="{881b03d5-21e5-4219-95d9-c98737917ff4}" symbol="0" label="-0.0289 - -0.0236" lower="-0.028880000000000" upper="-0.023629090909091"/>
    range_element = deepcopy(example)
    range_element.set('render','true')
    range_element.set('uuid',generate_uuid())
    range_element.set('symbol',str(index))
    range_element.set('label',str(min_val) + ' - ' + str(max_val))
    range_element.set('lower',str(min_val))
    range_element.set('upper',str(max_val))
    return range_element



def create_matplotlib_color_gradient_scale(limit):
    import matplotlib.pyplot as plt
    import numpy as np
    import colorsys
    from matplotlib.colors import LinearSegmentedColormap
    from matplotlib.cm import ScalarMappable
    # Generate color values
    number_of_elements = 100
    colors = [generate_color_values(i, number_of_elements) for i in range(number_of_elements)]
    colors = np.array(colors)[:, :3]  # Exclude alpha channel for colormap

    # Create custom colormap
    cmap = LinearSegmentedColormap.from_list('custom_cmap', colors)

    # Create a ScalarMappable and add colorbars
    sm = ScalarMappable(cmap=cmap)
    sm.set_array([])

    # Create a figure and add colorbars
    fig, ax = plt.subplots(figsize=(4, 2))  # Adjust the figsize to make the colorbar larger
    fig.subplots_adjust(bottom=0.5)

    # Add horizontal colorbar
    cbar = fig.colorbar(sm, orientation='vertical', ax=ax, shrink=1)
    cbar.set_label('Displacement rate (mm)')
    tick_values = np.linspace(0, 1, 5)
    tick_labels = np.linspace(-limit*1000, limit*1000, 5)
    cbar.set_ticks(tick_values)
    cbar.set_ticklabels(tick_labels)
    ax.remove()
    fig.savefig(f'res/qgis_colorbar_{limit*1000}mm_horizontal.png', dpi=300, bbox_inches='tight')

    fig.savefig(f'res/qgis_colorbar_{limit}_vertical.png', dpi=300, bbox_inches='tight')

    # Add vertical colorbar
    fig, ax = plt.subplots(figsize=(20, 10))  # Adjust the figsize to make the colorbar larger
    fig.subplots_adjust(bottom=0.5)
    cbar = fig.colorbar(sm, orientation='horizontal', ax=ax, shrink=1)
    cbar.set_label('Displacement rate (mm)')
    # big font
    cbar.set_ticklabels(tick_labels, fontsize=40, weight='bold')
    

    
    # big ticks
    cbar.ax.xaxis.set_tick_params(width=2)
    cbar.ax.yaxis.set_tick_params(width=2)
    # big font for labels
    cbar.ax.set_xlabel(cbar.ax.get_xlabel(), fontsize=40, weight='bold')

    tick_values = np.linspace(0, 1, 5)
    tick_labels = np.linspace(-limit*1000, limit*1000, 5)
    cbar.set_ticks(tick_values)
    cbar.set_ticklabels(tick_labels, fontsize=40, weight='bold')
    ax.remove()
    fig.savefig(f'res/qgis_colorbar_{limit*1000}mm_horizontal.png', dpi=300, bbox_inches='tight')


    

if __name__ == "__main__":
    one_sided_limit = 0.005
    number_of_elements = 10
    step = 2 * one_sided_limit / (number_of_elements)
    limits = []
    for i in range(number_of_elements):
        min_val = -one_sided_limit + i * step
        max_val = min_val + step
        limits.append((min_val, max_val))

    # round to 4 decimal places
    limits = [(round(min_val, 4), round(max_val, 4)) for min_val, max_val in limits]


    # add an offset to the limits
    offset = 0.0006
    limits = [(min_val + offset, max_val + offset) for min_val, max_val in limits]

    # set the first limit to -inf ish and the last limit to inf ish
    limits[0] = (-1000, limits[0][1])
    limits[-1] = (limits[-1][0], 1000)


    print(limits)
        
    # Load the XML file
    tree = ET.parse('res/qgis_symbology2.qml')
    root = tree.getroot()

    # Find the "ranges" element, in the "renderer-v2" element
    renderer = root.find('renderer-v2')
    ranges = renderer.find('ranges')

    # Get an example range element
    example = deepcopy(ranges[0])

    # remove the range elements
    ranges.clear()



    # Add the new range elements
    for i, (min_val, max_val) in enumerate(limits):
        range_element = generate_range_element(example, i, min_val, max_val)
        ranges.append(range_element)

    # Now we need to add the symbols
    symbols = renderer.find('symbols')
    symbols.clear()
    
    for i in range(number_of_elements):
        symbol = generate_symbol(i, number_of_elements)
        symbols.append(symbol)

    # Now we need to also update the color ramp
    colorramp = renderer.find('colorramp')
    options = colorramp.find('Option')
    # find the color1 option
    color1_option = options.find('Option[@name="color1"]')
    color1_option.set('value', generate_color(0, number_of_elements))
    color2_option = options.find('Option[@name="color2"]')
    color2_option.set('value', generate_color(number_of_elements - 1, number_of_elements))

    # now do the stops
    stops = options.find('Option[@name="stops"]')
    stops_value = ""
    for i in range(number_of_elements):
        if i == 0 or i == number_of_elements-1:
            continue
        # form 0.25;253,174,97,255;rgb;ccw: position, color, mode, direction?
        position = i / (number_of_elements)
        color = generate_color(i, number_of_elements)
        stops_value += f'{position};{color};rgb;ccw:'

    # remove the last colon
    stops_value = stops_value[:-1]

    # set the value
    stops.set('value', stops_value)

    # Save the XML file
    tree.write(f'res/qgis_style_{one_sided_limit}o.qml')

    # Create a matplotlib color gradient scale
    create_matplotlib_color_gradient_scale(one_sided_limit)
