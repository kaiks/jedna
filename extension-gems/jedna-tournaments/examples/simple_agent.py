#!/usr/bin/env python3
import json
import sys
from collections import Counter

class SimpleAgent:
    def run(self):
        while True:
            try:
                line = input()
                data = json.loads(line)
                
                if data['type'] == 'request_action':
                    action = self.decide_action(data['state'])
                    print(json.dumps(action))
                    sys.stdout.flush()
                elif data['type'] == 'game_end':
                    break
                    
            except EOFError:
                break
    
    def decide_action(self, state):
        # Simple strategy: play first playable card, otherwise draw
        if state.get('playable_cards') and len(state['playable_cards']) > 0:
            card = state['playable_cards'][0]
            action = {'action': 'play', 'card': card}
            
            # Add color for wild cards
            if card == 'w' or card.startswith('wd'):
                # Pick the color we have most of
                colors = [c[0] for c in state['hand'] if c[0] != 'w']
                if colors:
                    color_counts = Counter(colors)
                    best_color = color_counts.most_common(1)[0][0]
                else:
                    best_color = 'r'
                
                color_map = {'r': 'red', 'b': 'blue', 'g': 'green', 'y': 'yellow'}
                action['wild_color'] = color_map[best_color]
            
            return action
        elif 'draw' in state.get('available_actions', []):
            return {'action': 'draw'}
        else:
            return {'action': 'pass'}

if __name__ == '__main__':
    SimpleAgent().run()