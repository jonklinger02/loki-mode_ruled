/**
 * Task queue for Autonomi VSCode Extension
 */

import { Task, TaskStatus } from '../types/execution';

export class TaskQueue {
  private queue: Task[] = [];
  private processing: boolean = false;

  /**
   * Enqueue a task with priority ordering
   */
  enqueue(task: Task): void {
    // Insert in priority order (higher priority first)
    const insertIndex = this.queue.findIndex(t => t.priority < task.priority);
    if (insertIndex === -1) {
      this.queue.push(task);
    } else {
      this.queue.splice(insertIndex, 0, task);
    }
  }

  /**
   * Dequeue the highest priority task
   */
  dequeue(): Task | undefined {
    return this.queue.shift();
  }

  /**
   * Peek at the next task without removing it
   */
  peek(): Task | undefined {
    return this.queue[0];
  }

  /**
   * Clear all tasks from the queue
   */
  clear(): void {
    this.queue = [];
  }

  /**
   * Get all tasks in the queue
   */
  getAll(): Task[] {
    return [...this.queue];
  }

  /**
   * Get the number of tasks in the queue
   */
  size(): number {
    return this.queue.length;
  }

  /**
   * Check if the queue is empty
   */
  isEmpty(): boolean {
    return this.queue.length === 0;
  }

  /**
   * Check if currently processing
   */
  isProcessing(): boolean {
    return this.processing;
  }

  /**
   * Set processing state
   */
  setProcessing(processing: boolean): void {
    this.processing = processing;
  }

  /**
   * Remove a task by ID
   */
  remove(taskId: string): boolean {
    const index = this.queue.findIndex(t => t.id === taskId);
    if (index !== -1) {
      this.queue.splice(index, 1);
      return true;
    }
    return false;
  }

  /**
   * Get a task by ID
   */
  get(taskId: string): Task | undefined {
    return this.queue.find(t => t.id === taskId);
  }

  /**
   * Update a task in the queue
   */
  update(taskId: string, updates: Partial<Task>): boolean {
    const task = this.queue.find(t => t.id === taskId);
    if (task) {
      Object.assign(task, updates);
      return true;
    }
    return false;
  }

  /**
   * Get tasks by status
   */
  getByStatus(status: TaskStatus): Task[] {
    return this.queue.filter(t => t.status === status);
  }

  /**
   * Get tasks by priority
   */
  getByPriority(priority: number): Task[] {
    return this.queue.filter(t => t.priority === priority);
  }

  /**
   * Reorder task to a new position
   */
  reorder(taskId: string, newIndex: number): boolean {
    const currentIndex = this.queue.findIndex(t => t.id === taskId);
    if (currentIndex === -1 || newIndex < 0 || newIndex >= this.queue.length) {
      return false;
    }
    const [task] = this.queue.splice(currentIndex, 1);
    this.queue.splice(newIndex, 0, task);
    return true;
  }

  /**
   * Serialize queue to JSON
   */
  toJSON(): string {
    return JSON.stringify({
      queue: this.queue,
      processing: this.processing
    });
  }

  /**
   * Restore queue from JSON
   */
  fromJSON(json: string): void {
    try {
      const data = JSON.parse(json);
      this.queue = data.queue || [];
      this.processing = data.processing || false;
    } catch {
      this.queue = [];
      this.processing = false;
    }
  }
}
