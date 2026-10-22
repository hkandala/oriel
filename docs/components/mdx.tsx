import defaultMdxComponents from 'fumadocs-ui/mdx';
import { Step, Steps } from 'fumadocs-ui/components/steps';
import { Tab, Tabs } from 'fumadocs-ui/components/tabs';
import type { MDXComponents } from 'mdx/types';
import './design/design.css';
import { PillCard, PillsDemo } from './design/pills-demo';
import { SplitDemo } from './design/split-demo';
import { ChatCard, PanePicker, Phones } from './design/mocks';
import { Architecture, Flow, Ownership } from './design/diagrams';

export function getMDXComponents(components?: MDXComponents) {
  return {
    ...defaultMdxComponents,
    Step,
    Steps,
    Tab,
    Tabs,
    PillsDemo,
    PillCard,
    SplitDemo,
    ChatCard,
    PanePicker,
    Phones,
    Architecture,
    Flow,
    Ownership,
    ...components,
  } satisfies MDXComponents;
}

export const useMDXComponents = getMDXComponents;

declare global {
  type MDXProvidedComponents = ReturnType<typeof getMDXComponents>;
}
